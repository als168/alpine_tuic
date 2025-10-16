# Alpine TUIC 一键安装脚本

本项目提供一个适用于 **Alpine Linux** 的 TUIC v5 一键安装脚本，自动完成依赖安装、证书生成/申请、配置文件生成、OpenRC 服务创建，并输出订阅链接。

---

## 🚀 一键安装

复制并运行以下命令即可安装：

```bash
curl -fsSL https://raw.githubusercontent.com/als168/alpine_tuic/main/tuic.sh -o tuic.sh && chmod +x tuic.sh && sh tuic.sh
```

##⚙️ 功能特性
自动安装依赖（wget、curl、openssl、openrc 等）

支持自签证书 / ACME 证书

自动生成 UUID 和密码

自动生成配置文件 /etc/tuic/config.json

自动创建 OpenRC 服务 /etc/init.d/tuic

自动输出订阅链接（tuic://... 格式）

支持 IPv4 / IPv6

##📌 管理命令
```bash
service tuic start     # 启动服务
service tuic stop      # 停止服务
service tuic restart   # 重启服务
service tuic status    # 查看状态
cat /etc/tuic/config.json   # 查看配置文件
tail -f /var/log/tuic.log   # 查看实时日志
```
##❌ 卸载命令

```bash
service tuic stop
rc-update del tuic
rm /etc/init.d/tuic
rm /usr/local/bin/tuic
rm -rf /etc/tuic
rm tuic.sh
```


























 ```
