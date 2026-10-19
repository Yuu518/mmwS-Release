# 妙妙屋 S

基于 [妙妙屋](https://github.com/iluobei/miaomiaowu) 的订阅管理面板，加入了 sing-box 远程服务器管理：主控通过加密 WebSocket 管理各服务器上的 box-agent，可视化配置 sing-box 的入站、出站和路由，入站会自动生成订阅节点。

本仓库只用于发布：

- 面板：Docker 镜像 `ghcr.io/yuu518/miaomiaowus`
- Agent：本仓库 [Releases](https://github.com/Yuu518/mmwS-Release/releases) 中的 `box-agent-linux-amd64` / `box-agent-linux-arm64`（附 `sha256sums.txt`）

面板和 Agent 各自独立编号，版本号都不带 `v` 前缀，例如 `0.1.0`：

- 面板镜像的 tag 来自面板仓库的版本 tag，`latest` 指向最新正式版；面板「检查更新」读取的就是这里的镜像 tag，更新面板只替换容器，不影响各服务器上的 Agent。
- Agent 每次构建都会发布到本仓库 Releases：提交正好打了 tag 时是正式版（如 `0.1.0`），否则是带提交号的预发布版（如 `0.1.0-c45d06c`）。安装命令默认下载最新正式版。

## 安装面板（Docker）

```bash
curl -fsSL https://raw.githubusercontent.com/Yuu518/mmwS-Release/master/install.sh | sudo bash
```

脚本会自动安装 Docker Engine 与 Compose v2，询问数据库（SQLite 或 PostgreSQL 18）和面板端口（默认 `11996`），然后把面板部署到 `/opt/miaomiaowus`。安装完成后访问 `http://服务器IP:端口` 完成初始化。

无人值守安装：

```bash
curl -fsSL https://raw.githubusercontent.com/Yuu518/mmwS-Release/master/install.sh | sudo env MMW_DATABASE_DRIVER=sqlite PORT=11996 bash
```

更新到最新版本：

```bash
curl -fsSL https://raw.githubusercontent.com/Yuu518/mmwS-Release/master/install.sh | sudo bash -s update
```

指定版本：

```bash
curl -fsSL https://raw.githubusercontent.com/Yuu518/mmwS-Release/master/install.sh | sudo env MMW_VERSION=0.1.0 bash -s update
```

卸载（默认保留数据，设置 `MMW_KEEP_DATA=false` 可连数据一起删除）：

```bash
curl -fsSL https://raw.githubusercontent.com/Yuu518/mmwS-Release/master/install.sh | sudo bash -s uninstall
```

### 手动部署

```bash
mkdir -p /opt/miaomiaowus && cd /opt/miaomiaowus
curl -fsSLO https://raw.githubusercontent.com/Yuu518/mmwS-Release/master/docker-compose.yml
docker compose up -d
```

使用 PostgreSQL 时，在同目录的 `.env` 中设置 `MMW_DATABASE_DRIVER=postgres`、`MMW_DATABASE_HOST=postgres`、`MMW_DATABASE_PORT=5432`、`MMW_DATABASE_NAME`、`MMW_DATABASE_USER`、`MMW_DATABASE_PASSWORD`、`MMW_DATABASE_SSLMODE=disable`，再执行 `docker compose --profile postgres up -d`。

持久化目录：`data/`、`subscribes/`、`rule_templates/`、`postgres-data/`。

### 安装脚本环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `MMW_DATABASE_DRIVER` | `sqlite` 或 `postgres`，设置后跳过数据库选择 | 交互选择 |
| `PORT` | 面板对外端口 | `11996` |
| `MMW_VERSION` | 镜像版本 | `latest` |
| `MMW_IMAGE` | 镜像地址 | `ghcr.io/yuu518/miaomiaowus` |
| `MMW_DOCKER_DIR` | 安装目录 | `/opt/miaomiaowus` |
| `MMW_KEEP_DATA` | 卸载时是否保留数据 | 交互选择，默认保留 |

## 安装 Agent（二进制）

在面板「服务管理」中添加服务器，复制生成的安装命令，在远程服务器上以 root 执行。脚本会：

1. 从本仓库最新 Release 下载对应架构的 box-agent 并校验 sha256；服务器访问不了 GitHub 时改从主控下载（需要把二进制放到主控的 `data/agent-dist/`）。
2. 写入 `/etc/box-agent/config.yaml`，sing-box 数据放在 `/etc/box-agent/sing-box/`。
3. 注册 systemd / OpenRC 服务并启动。

执行安装命令前可以设置：

| 变量 | 说明 |
|------|------|
| `BOXA_VERSION` | 安装指定版本，例如 `0.1.0` |
| `BOXA_DOWNLOAD_URL` | 直接指定二进制下载地址 |
| `BOXA_RELEASE_REPO` | 从其它仓库的 Release 下载 |

面板容器可设置 `MMW_AGENT_RELEASE_REPO` 修改安装命令默认使用的 Release 仓库。

## 免责声明

- 本程序仅供学习交流使用，请勿用于非法用途
- 使用本程序需遵守当地法律法规
