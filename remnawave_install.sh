#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Функция для вывода с цветом
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${ORANGE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Функция для запроса ввода (читаем из /dev/tty для работы с curl | bash)
ask_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"

    if [ -n "$default" ]; then
        echo -ne "${ORANGE}${prompt}${NC} [${default}]: " > /dev/tty
        read -r input < /dev/tty
        input=${input:-$default}
    else
        echo -ne "${ORANGE}${prompt}${NC}: " > /dev/tty
        read -r input < /dev/tty
        while [ -z "$input" ]; do
            print_error "Это поле обязательно!"
            echo -ne "${ORANGE}${prompt}${NC}: " > /dev/tty
            read -r input < /dev/tty
        done
    fi

    eval "$var_name='$input'"
}

# Функция для подтверждения
ask_confirm() {
    local prompt="$1"
    echo -ne "${ORANGE}${prompt}${NC} (y/n): " > /dev/tty
    read -r confirm < /dev/tty
    [[ "$confirm" =~ ^[Yy]$ ]]
}

# Баннер
echo "=================================================="
echo "  Скрипт установки Remnawave Node + Selfsteal"
echo "=================================================="
echo ""

# Выбор режима установки
echo "Выберите компонент для установки:"
echo "1) Remnawave Node (Step 7)"
echo "2) Selfsteal SNI (Step 8)"
echo "3) Оба компонента"
echo -ne "${ORANGE}Ваш выбор (1-3):${NC} " > /dev/tty
read -r install_choice < /dev/tty

install_node=false
install_selfsteal=false

case $install_choice in
    1) install_node=true ;;
    2) install_selfsteal=true ;;
    3) install_node=true; install_selfsteal=true ;;
    *) print_error "Неверный выбор!"; exit 1 ;;
esac

echo ""

# ==========================================
# STEP 7: Remnawave Node
# ==========================================
if [ "$install_node" = true ]; then
    print_info "=== Шаг 7: Настройка Remnawave Node ==="
    echo ""

    # Обновление системы
    print_info "Обновление системы и установка curl..."
    if ! apt update > /dev/null 2>&1 && apt install -y curl > /dev/null 2>&1; then
        print_error "Ошибка при обновлении системы"
        exit 1
    fi
    print_success "Система обновлена, curl установлен"
    echo ""

    # Установка Docker
    print_info "Установка Docker..."
    if ! curl -fsSL https://get.docker.com | sh > /dev/null 2>&1; then
        print_error "Ошибка при установке Docker"
        exit 1
    fi
    print_success "Docker установлен"
    echo ""

    # Создание директории проекта
    print_info "Создание директории проекта..."
    mkdir -p /opt/remnanode && cd /opt/remnanode
    print_success "Директория создана: /opt/remnanode"
    echo ""

    # Запрос содержимого docker-compose.yml
    print_info "Теперь нужно вставить содержимое docker-compose.yml"
    print_info "Вставьте весь контент и нажмите Ctrl+D на новой строке для завершения:"
    echo ""

    COMPOSE_CONTENT=""
    while IFS= read -r line; do
        COMPOSE_CONTENT+="$line"$'\n'
    done < /dev/tty

    # Сохранение docker-compose.yml
    echo -e "$COMPOSE_CONTENT" > docker-compose.yml
    print_success "Файл docker-compose.yml создан"
    echo ""

    # Запуск контейнера
    if ask_confirm "Запустить контейнер Remnawave Node?"; then
        print_info "Запуск контейнера..."
        docker compose up -d && docker compose logs -f
    fi
    echo ""
fi

# ==========================================
# STEP 8: Selfsteal (SNI) Setup
# ==========================================
if [ "$install_selfsteal" = true ]; then
    print_info "=== Шаг 8: Настройка Selfsteal (SNI) ==="
    echo ""

    # Создание директории
    print_info "Создание рабочей директории..."
    mkdir -p /opt/selfsteel && cd /opt/selfsteel
    print_success "Директория создана: /opt/selfsteel"
    echo ""

    # Создание Caddyfile
    print_info "Создание Caddyfile..."
    cat > Caddyfile << 'EOF'
{
    https_port {$SELF_STEAL_PORT}
    default_bind 127.0.0.1
    servers {
        listener_wrappers {
            proxy_protocol {
                allow 127.0.0.1/32
            }
            tls
        }
    }
    auto_https disable_redirects
}

http://{$SELF_STEAL_DOMAIN} {
    bind 0.0.0.0
    redir https://{$SELF_STEAL_DOMAIN}{uri} permanent
}

https://{$SELF_STEAL_DOMAIN} {
    root * /var/www/html
    try_files {path} /index.html
    file_server

}


:{$SELF_STEAL_PORT} {
    tls internal
    respond 204
}

:80 {
    bind 0.0.0.0
    respond 204
}
EOF
    print_success "Caddyfile создан"
    echo ""

    # Настройка переменных окружения
    print_info "Настройка переменных окружения..."
    ask_input "Введите ваш домен (например, steel.domain.com)" DOMAIN
    ask_input "Введите порт для Selfsteal" PORT "9443"

    cat > .env << EOF
SELF_STEAL_DOMAIN=$DOMAIN
SELF_STEAL_PORT=$PORT
EOF
    print_success "Файл .env создан с доменом: $DOMAIN и портом: $PORT"
    echo ""

    # Создание docker-compose.yml
    print_info "Создание docker-compose.yml..."
    cat > docker-compose.yml << 'EOF'
services:
  caddy:
    image: caddy:latest
    container_name: caddy-remnawave
    restart: unless-stopped
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ../html:/var/www/html
      - ./logs:/var/log/caddy
      - caddy_data_selfsteal:/data
      - caddy_config_selfsteal:/config
    env_file:
      - .env
    network_mode: "host"

volumes:
  caddy_data_selfsteal:
  caddy_config_selfsteal:
EOF
    print_success "Файл docker-compose.yml создан"
    echo ""

    # Запуск и проверка
    if ask_confirm "Запустить Selfsteal контейнер?"; then
        print_info "Запуск контейнера..."
        docker compose up -d
        sleep 2
        print_info "Логи контейнера (Ctrl+C для выхода):"
        docker compose logs -f -t
    fi
    echo ""

    # Создание placeholder сайта
    print_info "Создание placeholder сайта..."
    mkdir -p /opt/html
    printf '%s\n' '<!doctype html><meta charset="utf-8"><title>Selfsteal</title><h1>It works.</h1>' \
      > /opt/html/index.html
    print_success "Placeholder сайт создан в /opt/html/index.html"
    echo ""
fi

# Завершение
echo "=================================================="
print_success "Установка завершена!"
echo "=================================================="

if [ "$install_node" = true ]; then
    echo "Remnawave Node: /opt/remnanode"
fi

if [ "$install_selfsteal" = true ]; then
    echo "Selfsteal: /opt/selfsteel"
    echo "HTML: /opt/html"
    echo "Домен: $DOMAIN:$PORT"
fi

echo ""
print_info "Для проверки логов используйте:"
if [ "$install_node" = true ]; then
    echo "  cd /opt/remnanode && docker compose logs -f"
fi
if [ "$install_selfsteal" = true ]; then
    echo "  cd /opt/selfsteel && docker compose logs -f"
fi
