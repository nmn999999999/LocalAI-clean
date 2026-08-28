#include "ssh_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <libssh2.h>

static void append_out(char *out, int out_len, const char *data, int datalen, int *total) {
    if (out == NULL || out_len <= 1) return;
    if (*total >= out_len - 1) return;
    int space = out_len - 1 - *total;
    int n = datalen < space ? datalen : space;
    if (n > 0) {
        memcpy(out + *total, data, n);
        *total += n;
        out[*total] = '\0';
    }
}

int ssh_exec(const char *host, int port, const char *user,
             int auth_type, const char *password,
             const char *privatekey_pem, const char *passphrase,
             const char *command,
             char *out_buf, int out_len) {
    if (out_buf && out_len > 0) out_buf[0] = '\0';
    int total = 0;
    int sock = -1;
    LIBSSH2_SESSION *session = NULL;
    int rc = 0;

    if (libssh2_init(0) != 0) {
        snprintf(out_buf, out_len, "libssh2 初始化失败");
        return -1;
    }

    struct addrinfo hints, *res = NULL;
    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%d", port > 0 ? port : 22);
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, portstr, &hints, &res) != 0) {
        snprintf(out_buf, out_len, "DNS 解析失败: %s", host ? host : "");
        libssh2_exit();
        return -2;
    }
    for (struct addrinfo *r = res; r; r = r->ai_next) {
        sock = socket(r->ai_family, r->ai_socktype, r->ai_protocol);
        if (sock < 0) continue;
        if (connect(sock, r->ai_addr, (socklen_t)r->ai_addrlen) == 0) break;
        close(sock);
        sock = -1;
    }
    freeaddrinfo(res);
    if (sock < 0) {
        snprintf(out_buf, out_len, "无法连接 %s:%d", host ? host : "", port > 0 ? port : 22);
        libssh2_exit();
        return -3;
    }

    session = libssh2_session_init();
    if (session == NULL) {
        close(sock);
        libssh2_exit();
        snprintf(out_buf, out_len, "SSH 会话初始化失败");
        return -4;
    }
    libssh2_session_set_blocking(session, 1);
    if (libssh2_session_handshake(session, sock) != 0) {
        snprintf(out_buf, out_len, "SSH 握手失败");
        libssh2_session_free(session);
        close(sock);
        libssh2_exit();
        return -5;
    }

    int auth_ok = 0;
    if (auth_type == 1) {
        const char *pk = privatekey_pem ? privatekey_pem : "";
        rc = libssh2_userauth_publickey_frommemory(session, user, strlen(user),
                                                   NULL, 0, pk, strlen(pk), passphrase);
        if (rc == 0) {
            auth_ok = 1;
        } else {
            char *errmsg = NULL;
            int errlen = 0;
            libssh2_session_last_error(session, &errmsg, &errlen, 0);
            snprintf(out_buf, out_len, "私钥认证失败: %s", errmsg ? errmsg : "未知错误");
        }
    } else {
        rc = libssh2_userauth_password(session, user, password ? password : "");
        if (rc == 0) {
            auth_ok = 1;
        } else {
            snprintf(out_buf, out_len, "密码认证失败");
        }
    }
    if (!auth_ok) {
        libssh2_session_disconnect(session, "auth failed");
        libssh2_session_free(session);
        close(sock);
        libssh2_exit();
        return -6;
    }

    LIBSSH2_CHANNEL *channel = libssh2_channel_open_session(session);
    if (channel == NULL) {
        snprintf(out_buf, out_len, "打开会话通道失败");
        libssh2_session_disconnect(session, "error");
        libssh2_session_free(session);
        close(sock);
        libssh2_exit();
        return -7;
    }
    if (libssh2_channel_exec(channel, command) != 0) {
        snprintf(out_buf, out_len, "执行命令失败");
        libssh2_channel_free(channel);
        libssh2_session_disconnect(session, "error");
        libssh2_session_free(session);
        close(sock);
        libssh2_exit();
        return -8;
    }

    char buf[4096];
    while ((rc = libssh2_channel_read(channel, buf, sizeof(buf))) > 0) {
        append_out(out_buf, out_len, buf, rc, &total);
    }
    while ((rc = libssh2_channel_read_stderr(channel, buf, sizeof(buf))) > 0) {
        append_out(out_buf, out_len, buf, rc, &total);
    }

    int exit_code = -1;
    exit_code = libssh2_channel_get_exit_status(channel);

    libssh2_channel_send_eof(channel);
    libssh2_channel_wait_closed(channel);
    libssh2_channel_free(channel);
    libssh2_session_disconnect(session, "normal");
    libssh2_session_free(session);
    close(sock);
    libssh2_exit();
    return exit_code;
}
