#!/usr/bin/env bash

app="keycompute"

echo ">>> build ${app}"

apt_install() {
    apt install -y podman
    apt install -y redis
    apt install -y postgresql
    apt install -y postgresql-contrib
    apt install -y librust-openssl-sys-dev
    apt install -y librust-glib-sys-dev
    apt install -y librust-cairo-sys-rs-dev
    apt install -y libgdk-pixbuf-2.0-dev
    apt install -y librust-atk-sys-dev
    apt install -y librust-pango-sys-dev
    apt install -y librust-gdk-dev
    apt install -y libsoup-3.0-dev
    apt install -y libjavascriptcoregtk-4.1-dev
    apt install -y libwebkit2gtk-4.1-dev
}

setting_podman() {
    cat >  /etc/containers/registries.conf << EOF
unqualified-search-registries = ["docker.io"]  # 默认还是搜docker.io
# 重点! 把镜像源地址“附魔”到docker.io前缀上!
[[registry]]
prefix = "docker.io"
location = "docker.1ms.run"       # 毫秒加速, YYDS
[[registry]]
prefix = "docker.io"
location = "hub.rat.dev"          # 鼠鼠快车, 稳
[[registry]]
prefix = "docker.io"
location = "docker.xuanyuan.me"   # 轩辕快递, 使命必达
[[registry]]
prefix = "docker.io"
location = "docker.1panel.live"   # 1Panel专线, 官方认证
EOF
}

start_services() {
    # PostgreSQL 配置
    PG_VERSION="15"  # 根据你的版本修改
    PG_DATA="/var/lib/postgresql/${PG_VERSION}/main"
    PG_LOG="/var/log/postgresql/postgresql.log"
    PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

    # Redis 配置
    REDIS_CONFIG="/etc/redis/redis.conf"

    echo "Starting PostgreSQL..."

    [ ! -e ${PG_DATA}/postgresql.conf ] && touch ${PG_DATA}/postgresql.conf
    cat > ${PG_DATA}/pg_hba.conf << EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" 是 Unix 域套接字连接
local   all             all                                     peer

# IPv4 本地连接
host    all             all             127.0.0.1/32            scram-sha-256

# IPv6 本地连接
host    all             all             ::1/128                 scram-sha-256

# 允许同一网络内的连接（可选，根据需要调整）
# host    all             all             192.168.1.0/24          scram-sha-256
EOF

    su postgres -c "${PG_BIN}/pg_ctl start -D ${PG_DATA} -l ${PG_LOG}"


    if [ $? -eq 0 ]; then
        echo "PostgreSQL started successfully"
    else
        echo "PostgreSQL failed to start"
    fi


    echo "Starting Redis..."
    redis-server ${REDIS_CONFIG}

    if [ $? -eq 0 ]; then
        echo "Redis started successfully"
    else
        echo "Redis failed to start"
    fi

    # 等待服务启动
    sleep 2

    # 设置密码和创建数据库
    su postgres -c "psql" << EOF
ALTER USER postgres WITH PASSWORD 'your_strong_password';
CREATE DATABASE keycompute OWNER keycompute;
CREATE USER keycompute WITH PASSWORD 'ObpipdGz00wLxK1u1OupDP4rWVu1NEUpB5QGIiIGbek=';
GRANT ALL PRIVILEGES ON DATABASE keycompute TO keycompute;
EOF

    # 测试连接
    echo "Testing PostgreSQL connection..."
    su postgres -c "${PG_BIN}/psql -c \"SELECT version();\"" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "PostgreSQL is responding"
    else
        echo "PostgreSQL is not responding"
    fi

    echo "Testing Redis connection..."
    redis-cli -a "1VoCAza2HoaOmCafAdM+oxj165CiYpgp2XmD9tTeLN0=" ping > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Redis is responding"
    else
        echo "Redis is not responding"
    fi

}

stop_services() {
    PG_VERSION="15"
    PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
    PG_DATA="/var/lib/postgresql/${PG_VERSION}/main"

    echo "Stopping PostgreSQL..."
    su postgres -c "${PG_BIN}/pg_ctl stop -D ${PG_DATA}"

    echo "Stopping Redis..."
    redis-cli -a "1VoCAza2HoaOmCafAdM+oxj165CiYpgp2XmD9tTeLN0=" shutdown

    echo "Services stopped"
}

if [ -n "$1" ]; then
    if [ start == "$1" ]; then
        start_services
    fi
    if [ stop == "$1" ]; then
        stop_services
    fi
    if [ server == "$1" ]; then
        export KC__DATABASE__URL="postgres://keycompute:ObpipdGz00wLxK1u1OupDP4rWVu1NEUpB5QGIiIGbek=@localhost:5432/keycompute"
        export KC__REDIS__URL="redis://:1VoCAza2HoaOmCafAdM+oxj165CiYpgp2XmD9tTeLN0=@localhost:6379"
        export KC__AUTH__JWT_SECRET="ea2fe6dd660639d1401c0c4c9fbd71cfe627785ae2359f3b0179efa7c0e24245f966a586295ed598db795da5a942dff7"
        export KC__CRYPTO__SECRET_KEY="H8AS+HwrYBp/KSAWRLh9jcLnsV+SIvOtohDPRun+GXA="
        export KC__EMAIL__SMTP_HOST="smtp.example.com"
        export KC__EMAIL__SMTP_PORT="587"
        export KC__EMAIL__SMTP_USERNAME="noreply@example.com"
        export KC__EMAIL__SMTP_PASSWORD="your-smtp-password"
        export KC__EMAIL__FROM_ADDRESS="noreply@example.com"
        export KC__EMAIL__VERIFICATION_BASE_URL="https://api.example.com"
        export KC__DEFAULT_ADMIN_EMAIL="admin@keycompute.local"
        export KC__DEFAULT_ADMIN_PASSWORD="Admin@1q2w3e"
        pushd keycompute
            cargo run -p keycompute-server --features redis
        popd
    fi

    exit 0
fi

apt_install
setting_podman

[ ! -d ${app} ] && git clone https://github.com/rayylee/${app}
pushd ${app}
    cargo build --workspace --exclude desktop --exclude mobile --verbose
popd

