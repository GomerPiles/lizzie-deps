/* Runs a QUIC connection between an ngtcp2 client and server in memory: the
 * TLS 1.3 handshake through BoringSSL, a request and reply on one stream, and
 * a datagram. The server's ECDSA certificate is generated here, valid for 13
 * days, and the client accepts it only by its SHA-256 hash, as browsers do for
 * WebTransport. There are no sockets, threads or clocks: time advances by the
 * loop, and ngtcp2 takes randomness from BoringSSL through a callback. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <ngtcp2/ngtcp2.h>
#include <ngtcp2/ngtcp2_crypto.h>
#include <ngtcp2/ngtcp2_crypto_boringssl.h>
#include <openssl/ec_key.h>
#include <openssl/evp.h>
#include <openssl/mem.h>
#include <openssl/nid.h>
#include <openssl/pool.h>
#include <openssl/rand.h>
#include <openssl/sha.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#define CHECK(expr)                                                        \
  do {                                                                     \
    if (!(expr)) {                                                         \
      fprintf(stderr, "smoke: %s:%d: %s failed\n", __FILE__, __LINE__, #expr); \
      exit(1);                                                             \
    }                                                                      \
  } while (0)

#define CHECK_NGTCP2(call)                                                    \
  do {                                                                        \
    int rv_ = (call);                                                         \
    if (rv_ != 0) {                                                           \
      fprintf(stderr, "smoke: %s:%d: %s: %s\n", __FILE__, __LINE__, #call,    \
              ngtcp2_strerror(rv_));                                          \
      exit(1);                                                                \
    }                                                                         \
  } while (0)

static const uint8_t alpn[] = "\x06lizzie";
static const uint8_t request[] = "commands";
static const uint8_t reply[] = "tick";
static const uint8_t datagram[] = "redundant commands";

typedef struct Peer {
  const char *name;
  ngtcp2_conn *conn;
  SSL *ssl;
  ngtcp2_crypto_conn_ref ref;
  ngtcp2_sockaddr_in local;
  ngtcp2_sockaddr_in remote;
  int handshake_completed;
  int64_t stream_id;
  uint8_t received[64];
  size_t received_len;
  int received_fin;
  int received_datagram;
} Peer;

static ngtcp2_tstamp now = 1000 * NGTCP2_SECONDS;
static uint8_t certificate_hash[SHA256_DIGEST_LENGTH];

static ngtcp2_conn *get_conn(ngtcp2_crypto_conn_ref *ref) {
  return ((Peer *)ref->user_data)->conn;
}

static void random_bytes(uint8_t *dest, size_t len, const ngtcp2_rand_ctx *ctx) {
  (void)ctx;
  CHECK(RAND_bytes(dest, len));
}

static int new_connection_id(ngtcp2_conn *conn, ngtcp2_cid *cid,
                             ngtcp2_stateless_reset_token *token, size_t len,
                             void *user_data) {
  (void)conn;
  (void)user_data;
  cid->datalen = len;
  if (!RAND_bytes(cid->data, len) ||
      !RAND_bytes(token->data, sizeof(token->data))) {
    return NGTCP2_ERR_CALLBACK_FAILURE;
  }
  return 0;
}

static int handshake_completed(ngtcp2_conn *conn, void *user_data) {
  (void)conn;
  ((Peer *)user_data)->handshake_completed = 1;
  return 0;
}

static int recv_stream_data(ngtcp2_conn *conn, uint32_t flags, int64_t stream_id,
                            uint64_t offset, const uint8_t *data, size_t len,
                            void *user_data, void *stream_user_data) {
  Peer *peer = user_data;
  (void)stream_user_data;
  if (offset != peer->received_len ||
      len > sizeof(peer->received) - peer->received_len) {
    return NGTCP2_ERR_CALLBACK_FAILURE;
  }
  memcpy(peer->received + peer->received_len, data, len);
  peer->received_len += len;
  peer->received_fin = (flags & NGTCP2_STREAM_DATA_FLAG_FIN) != 0;
  peer->stream_id = stream_id;
  CHECK_NGTCP2(ngtcp2_conn_extend_max_stream_offset(conn, stream_id, len));
  ngtcp2_conn_extend_max_offset(conn, len);
  return 0;
}

static int recv_datagram(ngtcp2_conn *conn, uint32_t flags, const uint8_t *data,
                         size_t len, void *user_data) {
  (void)conn;
  (void)flags;
  Peer *peer = user_data;
  peer->received_datagram =
      len == sizeof(datagram) && memcmp(data, datagram, len) == 0;
  return 0;
}

static ngtcp2_callbacks callbacks(int server) {
  ngtcp2_callbacks cb;
  memset(&cb, 0, sizeof(cb));
  if (server) {
    cb.recv_client_initial = ngtcp2_crypto_recv_client_initial_cb;
  } else {
    cb.client_initial = ngtcp2_crypto_client_initial_cb;
    cb.recv_retry = ngtcp2_crypto_recv_retry_cb;
  }
  cb.recv_crypto_data = ngtcp2_crypto_recv_crypto_data_cb;
  cb.encrypt = ngtcp2_crypto_encrypt_cb;
  cb.decrypt = ngtcp2_crypto_decrypt_cb;
  cb.hp_mask = ngtcp2_crypto_hp_mask_cb;
  cb.update_key = ngtcp2_crypto_update_key_cb;
  cb.delete_crypto_aead_ctx = ngtcp2_crypto_delete_crypto_aead_ctx_cb;
  cb.delete_crypto_cipher_ctx = ngtcp2_crypto_delete_crypto_cipher_ctx_cb;
  cb.get_path_challenge_data2 = ngtcp2_crypto_get_path_challenge_data2_cb;
  cb.version_negotiation = ngtcp2_crypto_version_negotiation_cb;
  cb.rand = random_bytes;
  cb.get_new_connection_id2 = new_connection_id;
  cb.handshake_completed = handshake_completed;
  cb.recv_stream_data = recv_stream_data;
  cb.recv_datagram = recv_datagram;
  return cb;
}

static ngtcp2_path path_of(Peer *peer) {
  ngtcp2_path path;
  memset(&path, 0, sizeof(path));
  path.local.addr = (ngtcp2_sockaddr *)&peer->local;
  path.local.addrlen = sizeof(peer->local);
  path.remote.addr = (ngtcp2_sockaddr *)&peer->remote;
  path.remote.addrlen = sizeof(peer->remote);
  return path;
}

static void settings_and_params(ngtcp2_settings *settings,
                                ngtcp2_transport_params *params) {
  ngtcp2_settings_default(settings);
  settings->initial_ts = now;
  ngtcp2_transport_params_default(params);
  params->initial_max_streams_bidi = 1;
  params->initial_max_stream_data_bidi_local = 65536;
  params->initial_max_stream_data_bidi_remote = 65536;
  params->initial_max_data = 65536;
  params->max_datagram_frame_size = 1200;
}

static void random_cid(ngtcp2_cid *cid, size_t len) {
  cid->datalen = len;
  CHECK(RAND_bytes(cid->data, len));
}

static void generate_certificate(EVP_PKEY **key_out, X509 **certificate_out) {
  EC_KEY *ec = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
  CHECK(ec != NULL && EC_KEY_generate_key(ec));
  EVP_PKEY *key = EVP_PKEY_new();
  CHECK(key != NULL && EVP_PKEY_assign_EC_KEY(key, ec));

  X509 *certificate = X509_new();
  CHECK(certificate != NULL);
  CHECK(X509_set_version(certificate, X509_VERSION_3));
  CHECK(ASN1_INTEGER_set_int64(X509_get_serialNumber(certificate), 1));
  CHECK(X509_gmtime_adj(X509_getm_notBefore(certificate), 0));
  CHECK(X509_gmtime_adj(X509_getm_notAfter(certificate), 13 * 24 * 60 * 60));
  X509_NAME *name = X509_get_subject_name(certificate);
  CHECK(X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_UTF8,
                                   (const uint8_t *)"lizzie", -1, -1, 0));
  CHECK(X509_set_issuer_name(certificate, name));
  CHECK(X509_set_pubkey(certificate, key));
  CHECK(X509_sign(certificate, key, EVP_sha256()));

  uint8_t *der = NULL;
  int der_len = i2d_X509(certificate, &der);
  CHECK(der_len > 0);
  SHA256(der, (size_t)der_len, certificate_hash);
  OPENSSL_free(der);
  *key_out = key;
  *certificate_out = certificate;
}

static enum ssl_verify_result_t verify_by_hash(SSL *ssl, uint8_t *alert) {
  const STACK_OF(CRYPTO_BUFFER) *chain = SSL_get0_peer_certificates(ssl);
  uint8_t hash[SHA256_DIGEST_LENGTH];
  if (chain == NULL || sk_CRYPTO_BUFFER_num(chain) == 0) {
    *alert = SSL_AD_BAD_CERTIFICATE;
    return ssl_verify_invalid;
  }
  const CRYPTO_BUFFER *leaf = sk_CRYPTO_BUFFER_value(chain, 0);
  SHA256(CRYPTO_BUFFER_data(leaf), CRYPTO_BUFFER_len(leaf), hash);
  if (CRYPTO_memcmp(hash, certificate_hash, sizeof(hash)) != 0) {
    *alert = SSL_AD_BAD_CERTIFICATE;
    return ssl_verify_invalid;
  }
  return ssl_verify_ok;
}

static int select_alpn(SSL *ssl, const uint8_t **out, uint8_t *out_len,
                       const uint8_t *in, unsigned in_len, void *arg) {
  (void)ssl;
  (void)arg;
  for (unsigned i = 0; i < in_len; i += 1u + in[i]) {
    if (in[i] == alpn[0] && i + 1u + in[i] <= in_len &&
        memcmp(in + i + 1, alpn + 1, alpn[0]) == 0) {
      *out = in + i + 1;
      *out_len = in[i];
      return SSL_TLSEXT_ERR_OK;
    }
  }
  return SSL_TLSEXT_ERR_ALERT_FATAL;
}

static SSL_CTX *tls_context(int server, EVP_PKEY *key, X509 *certificate) {
  SSL_CTX *ctx = SSL_CTX_new(TLS_method());
  CHECK(ctx != NULL);
  CHECK(SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION));
  CHECK(SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION));
  if (server) {
    CHECK(ngtcp2_crypto_boringssl_configure_server_context(ctx) == 0);
    CHECK(SSL_CTX_use_certificate(ctx, certificate));
    CHECK(SSL_CTX_use_PrivateKey(ctx, key));
    SSL_CTX_set_alpn_select_cb(ctx, select_alpn, NULL);
  } else {
    CHECK(ngtcp2_crypto_boringssl_configure_client_context(ctx) == 0);
    SSL_CTX_set_custom_verify(ctx, SSL_VERIFY_PEER, verify_by_hash);
  }
  return ctx;
}

static void attach_tls(Peer *peer, SSL_CTX *ctx, int server) {
  peer->ssl = SSL_new(ctx);
  CHECK(peer->ssl != NULL);
  peer->ref.get_conn = get_conn;
  peer->ref.user_data = peer;
  SSL_set_app_data(peer->ssl, &peer->ref);
  if (server) {
    SSL_set_accept_state(peer->ssl);
  } else {
    SSL_set_connect_state(peer->ssl);
    CHECK(SSL_set_alpn_protos(peer->ssl, alpn, sizeof(alpn) - 1) == 0);
    CHECK(SSL_set_tlsext_host_name(peer->ssl, "localhost"));
  }
  ngtcp2_conn_set_tls_native_handle(peer->conn, peer->ssl);
}

/* Delivers one packet. The server's connection starts with the client's first
 * packet, as a real server's would. */
static void deliver(Peer *to, SSL_CTX *server_ctx, const uint8_t *packet,
                    size_t len) {
  ngtcp2_path path = path_of(to);
  ngtcp2_pkt_info info;
  memset(&info, 0, sizeof(info));
  if (to->conn == NULL) {
    ngtcp2_pkt_hd header;
    CHECK_NGTCP2(ngtcp2_accept(&header, packet, len));
    ngtcp2_settings settings;
    ngtcp2_transport_params params;
    settings_and_params(&settings, &params);
    params.original_dcid = header.dcid;
    params.original_dcid_present = 1;
    ngtcp2_cid scid;
    random_cid(&scid, NGTCP2_MAX_CIDLEN);
    ngtcp2_callbacks cb = callbacks(1);
    CHECK_NGTCP2(ngtcp2_conn_server_new(&to->conn, &header.scid, &scid, &path,
                                        header.version, &cb, &settings, &params,
                                        NULL, to));
    attach_tls(to, server_ctx, 1);
  }
  CHECK_NGTCP2(ngtcp2_conn_read_pkt(to->conn, &path, &info, packet, len, now));
}

/* Sends everything `from` has queued. A pending stream write or datagram goes
 * first; the flags report whether ngtcp2 accepted it. */
static void flush(Peer *from, Peer *to, SSL_CTX *server_ctx,
                  const uint8_t *stream_data, size_t stream_len,
                  int *stream_sent, int *datagram_sent) {
  if (from->conn == NULL) {
    return;
  }
  for (;;) {
    uint8_t packet[1452];
    ngtcp2_path_storage storage;
    ngtcp2_path_storage_zero(&storage);
    ngtcp2_pkt_info info;
    ngtcp2_ssize written;
    if (stream_data != NULL && !*stream_sent) {
      ngtcp2_vec data = {(uint8_t *)stream_data, stream_len};
      ngtcp2_ssize accepted = -1;
      written = ngtcp2_conn_writev_stream(
          from->conn, &storage.path, &info, packet, sizeof(packet), &accepted,
          NGTCP2_WRITE_STREAM_FLAG_FIN, from->stream_id, &data, 1, now);
      *stream_sent = accepted == (ngtcp2_ssize)stream_len;
    } else if (datagram_sent != NULL && !*datagram_sent) {
      int accepted = 0;
      written = ngtcp2_conn_write_datagram(from->conn, &storage.path, &info,
                                           packet, sizeof(packet), &accepted, 0,
                                           1, datagram, sizeof(datagram), now);
      *datagram_sent = accepted;
    } else {
      written = ngtcp2_conn_write_pkt(from->conn, &storage.path, &info, packet,
                                      sizeof(packet), now);
    }
    if (written < 0) {
      fprintf(stderr, "smoke: %s write: %s\n", from->name,
              ngtcp2_strerror((int)written));
      exit(1);
    }
    if (written == 0) {
      break;
    }
    deliver(to, server_ctx, packet, (size_t)written);
  }
  ngtcp2_conn_update_pkt_tx_time(from->conn, now);
}

static void handle_expiry(Peer *peer) {
  if (peer->conn != NULL && ngtcp2_conn_get_expiry(peer->conn) <= now) {
    CHECK_NGTCP2(ngtcp2_conn_handle_expiry(peer->conn, now));
  }
}

int main(void) {
  EVP_PKEY *key;
  X509 *certificate;
  generate_certificate(&key, &certificate);
  SSL_CTX *server_ctx = tls_context(1, key, certificate);
  SSL_CTX *client_ctx = tls_context(0, NULL, NULL);

  Peer client, server;
  memset(&client, 0, sizeof(client));
  memset(&server, 0, sizeof(server));
  client.name = "client";
  server.name = "server";
  client.stream_id = server.stream_id = -1;
  client.local.sin_family = server.local.sin_family = NGTCP2_AF_INET;
  client.local.sin_port = 1;
  server.local.sin_port = 2;
  client.remote = server.local;
  server.remote = client.local;

  ngtcp2_settings settings;
  ngtcp2_transport_params params;
  settings_and_params(&settings, &params);
  ngtcp2_cid dcid, scid;
  random_cid(&dcid, NGTCP2_MIN_INITIAL_DCIDLEN);
  random_cid(&scid, NGTCP2_MAX_CIDLEN);
  ngtcp2_path path = path_of(&client);
  ngtcp2_callbacks cb = callbacks(0);
  CHECK_NGTCP2(ngtcp2_conn_client_new(&client.conn, &dcid, &scid, &path,
                                      NGTCP2_PROTO_VER_V1, &cb, &settings,
                                      &params, NULL, &client));
  attach_tls(&client, client_ctx, 0);

  int request_sent = 0, datagram_sent = 0, reply_sent = 0, done = 0;
  for (int step = 0; step < 1000 && !done; ++step) {
    const uint8_t *client_stream = NULL;
    if (client.handshake_completed && client.stream_id < 0) {
      CHECK_NGTCP2(ngtcp2_conn_open_bidi_stream(client.conn, &client.stream_id, NULL));
    }
    if (client.stream_id >= 0) {
      client_stream = request;
    }
    flush(&client, &server, server_ctx, client_stream, sizeof(request),
          &request_sent, client_stream != NULL ? &datagram_sent : NULL);
    const uint8_t *server_stream =
        server.received_fin && server.received_len == sizeof(request) &&
                memcmp(server.received, request, sizeof(request)) == 0
            ? reply
            : NULL;
    flush(&server, &client, server_ctx, server_stream, sizeof(reply),
          &reply_sent, NULL);
    done = client.received_fin && client.received_len == sizeof(reply) &&
           memcmp(client.received, reply, sizeof(reply)) == 0 &&
           server.received_datagram;
    now += NGTCP2_MILLISECONDS;
    handle_expiry(&client);
    handle_expiry(&server);
  }
  CHECK(client.handshake_completed && server.handshake_completed);
  CHECK(done);

  printf("smoke: ngtcp2 %s, %s with %s: handshake, stream and datagram ok\n",
         ngtcp2_version(0)->version_str,
         SSL_CIPHER_get_name(SSL_get_current_cipher(client.ssl)),
         SSL_get_group_name(SSL_get_group_id(client.ssl)));

  ngtcp2_conn_del(client.conn);
  ngtcp2_conn_del(server.conn);
  SSL_free(client.ssl);
  SSL_free(server.ssl);
  SSL_CTX_free(client_ctx);
  SSL_CTX_free(server_ctx);
  X509_free(certificate);
  EVP_PKEY_free(key);
  return 0;
}
