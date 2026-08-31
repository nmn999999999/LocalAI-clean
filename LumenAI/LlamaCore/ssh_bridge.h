#ifndef ssh_bridge_h
#define ssh_bridge_h

#ifdef __cplusplus
extern "C" {
#endif

/*
 * 在远程主机执行一条命令并返回输出。
 * auth_type: 0 = 密码, 1 = 公钥(PEM 私钥字符串)
 * 返回: >=0 为远程退出码; <0 为本地/协议错误(错误信息写入 out_buf)
 */
int ssh_exec(const char *host,
             int port,
             const char *user,
             int auth_type,
             const char *password,
             const char *privatekey_pem,
             const char *passphrase,
             const char *command,
             char *out_buf,
             int out_len);

#ifdef __cplusplus
}
#endif

#endif /* ssh_bridge_h */
