# Nezha Runner

一键运行哪吒探针 Agent 的脚本。

---

## 使用方法

在服务器上直接执行以下命令即可自动下载并运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qq525448560/nezha-runner/main/nezha-run.sh)

---

##如果你想覆盖默认参数，可以在运行前设置环境变量，例如：

```bash
NZ_SERVER="nz.example.com:8008" NZ_CLIENT_SECRET="your_secret_here" bash <(curl -fsSL https://raw.githubusercontent.com/qq525448560/nezha-runner/main/nezha-run.sh)
