#!/bin/bash

# SOCKS5 Proxy Server Management Script
# Автоматическая установка и управление Dante SOCKS5 прокси-серверами

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_DIR="/etc/dante"
USERS_FILE="$CONFIG_DIR/users.txt"
SERVICES_FILE="$CONFIG_DIR/services.txt"

# Функции цветного вывода
print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# АВТОУСТАНОВКА СКРИПТА
auto_install() {
    local script_name="socks"
    local install_path="/usr/local/bin/$script_name"
    
    # Проверяем, не установлен ли уже скрипт
    if [[ "$0" != "$install_path" ]] && [[ ! -f "$install_path" ]]; then
        print_header "АВТОМАТИЧЕСКАЯ УСТАНОВКА"
        print_status "Установка команды '$script_name' в систему..."
        
        # Копируем скрипт в системную папку
        cp "$0" "$install_path"
        chmod +x "$install_path"
        
        # Создаем упрощенную wrapper функцию
        cat > /usr/local/bin/socks-wrapper.sh << 'EOF'
#!/bin/bash
socks() {
    local script_path="/usr/local/bin/socks"
    
    case "${1:-menu}" in
        "help"|"-h"|"--help")
            echo -e "\033[0;34mSOCKS5 Proxy Manager\033[0m"
            echo "Использование: socks"
            echo ""
            echo "Команда запускает интерактивное меню для управления SOCKS5 прокси-серверами"
            echo ""
            echo "Возможности:"
            echo "  • Просмотр всех подключений"
            echo "  • Создание новых подключений"
            echo "  • Удаление подключений"
            echo "  • Полное удаление системы"
            ;;
        *)
            sudo "$script_path"
            ;;
    esac
}

# Экспортируем функцию
export -f socks
EOF

        chmod +x /usr/local/bin/socks-wrapper.sh
        
        # Добавляем функцию в bashrc для всех пользователей
        if ! grep -q "socks-wrapper.sh" /etc/bash.bashrc 2>/dev/null; then
            echo "" >> /etc/bash.bashrc
            echo "# SOCKS5 Proxy Manager" >> /etc/bash.bashrc
            echo "source /usr/local/bin/socks-wrapper.sh" >> /etc/bash.bashrc
        fi
        
        # Добавляем и в профиль пользователя root
        if ! grep -q "socks-wrapper.sh" /root/.bashrc 2>/dev/null; then
            echo "" >> /root/.bashrc
            echo "# SOCKS5 Proxy Manager" >> /root/.bashrc  
            echo "source /usr/local/bin/socks-wrapper.sh" >> /root/.bashrc
        fi
        
        print_status "Установка завершена!"
        print_status "Команда '$script_name' теперь доступна глобально"
        echo ""
        echo -e "${CYAN}Использование:${NC}"
        echo "  socks       # интерактивное меню"
        echo "  socks help  # справка"
        echo ""
        
        read -p "Нажмите Enter для перехода в меню..."
        exec "$install_path"
    fi
}

# Проверка прав администратора
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Создание директории конфигурации
create_config_dir() {
    mkdir -p $CONFIG_DIR
    touch $USERS_FILE $SERVICES_FILE
}

# Функция для генерации случайного порта
generate_random_port() {
    while :; do
        port=$((RANDOM % 64512 + 1024))
        if ! ss -tulnp | awk '{print $4}' | grep -q ":$port" && ! grep -q ":$port:" $SERVICES_FILE 2>/dev/null; then
            echo $port
            return
        fi
    done
}

# Установка зависимостей
install_dependencies() {
    print_status "Обновление пакетов и установка зависимостей..."
    apt update > /dev/null 2>&1 && apt install -y dante-server apache2-utils > /dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        print_error "Ошибка при установке пакетов"
        exit 1
    fi
}

# Просмотр всех подключений
show_connections() {
    print_header "АКТИВНЫЕ ПОДКЛЮЧЕНИЯ"
    
    if [[ ! -s $SERVICES_FILE ]]; then
        print_warning "Нет активных подключений"
        return
    fi
    
    local ip=$(curl -4 -s ifconfig.me 2>/dev/null)
    echo -e "${CYAN}Внешний IP: $ip${NC}"
    echo ""
    
    local counter=1
    while IFS=':' read -r username port password service_name; do
        echo -e "${BLUE}Подключение #$counter${NC}"
        echo "  Имя: $service_name"
        echo "  Порт: $port"
        echo "  Логин: $username"
        echo "  Пароль: $password"
        echo "  Статус: $(systemctl is-active danted-$port 2>/dev/null || echo 'неактивно')"
        echo ""
        echo -e "${CYAN}Строки подключения:${NC}"
        echo "  $ip:$port:$username:$password"
        echo "  $username:$password@$ip:$port"
        echo "---"
        ((counter++))
    done < $SERVICES_FILE
}

# Создание нового подключения
create_connection() {
    print_header "СОЗДАНИЕ НОВОГО ПОДКЛЮЧЕНИЯ"
    
    # Имя подключения
    read -p "Имя подключения (по умолчанию: socks-$(date +%s)): " connection_name
    if [[ -z "$connection_name" ]]; then
        connection_name="socks-$(date +%s)"
    fi
    
    # Аутентификация
    read -p "Ввести логин и пароль вручную? [y/N]: " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        read -p "Имя пользователя: " username
        read -s -p "Пароль: " password
        echo ""
    else
        username=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 8)
        password=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 12)
        print_status "Сгенерированы учетные данные:"
        echo "  Логин: $username"
        echo "  Пароль: $password"
    fi
    
    # Порт
    read -p "Указать порт вручную? [y/N]: " port_choice
    if [[ "$port_choice" =~ ^[Yy]$ ]]; then
        while :; do
            read -p "Введите порт (1024-65535): " port
            if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] && 
               ! ss -tulnp | awk '{print $4}' | grep -q ":$port" && 
               ! grep -q ":$port:" $SERVICES_FILE 2>/dev/null; then
                break
            else
                print_warning "Порт недоступен или занят. Попробуйте снова."
            fi
        done
    else
        port=$(generate_random_port)
        print_status "Назначен порт: $port"
    fi
    
    # Определение интерфейса
    INTERFACE=$(ip route get 8.8.8.8 | awk -- '{print $5}' | head -n 1)
    print_status "Обнаружен сетевой интерфейс: $INTERFACE"
    
    # Создание пользователя
    print_status "Создание системного пользователя..."
    useradd -r -s /bin/false $username 2>/dev/null
    (echo "$password"; echo "$password") | passwd $username > /dev/null 2>&1
    
    # Создание конфигурации
    print_status "Создание конфигурации..."
    cat > /etc/danted-$port.conf <<EOL
logoutput: stderr
internal: 0.0.0.0 port = $port
external: $INTERFACE
socksmethod: username
user.privileged: root
user.notprivileged: nobody

client pass {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        log: error
}

socks pass {
        from: 0.0.0.0/0 to: 0.0.0.0/0
        method: username
        protocol: tcp udp
        log: error
}
EOL
    
    # Создание systemd сервиса
    cat > /etc/systemd/system/danted-$port.service <<EOL
[Unit]
Description=Dante SOCKS5 server on port $port
After=network.target

[Service]
Type=forking
User=root
ExecStart=/usr/sbin/danted -f /etc/danted-$port.conf
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/danted-$port.pid

[Install]
WantedBy=multi-user.target
EOL
    
    # Настройка брандмауэра и запуск
    print_status "Настройка брандмауэра и запуск службы..."
    ufw allow $port/tcp > /dev/null 2>&1
    systemctl daemon-reload
    systemctl start danted-$port
    systemctl enable danted-$port > /dev/null 2>&1
    
    if systemctl is-active --quiet danted-$port; then
        # Сохранение информации о подключении
        echo "$username:$port:$password:$connection_name" >> $SERVICES_FILE
        
        local ip=$(curl -4 -s ifconfig.me 2>/dev/null)
        print_status "Подключение '$connection_name' успешно создано!"
        echo ""
        echo -e "${CYAN}Параметры подключения:${NC}"
        echo "  IP: $ip:$port"
        echo "  Логин: $username"  
        echo "  Пароль: $password"
        echo ""
        echo -e "${CYAN}Строки для браузеров:${NC}"
        echo "  $ip:$port:$username:$password"
        echo "  $username:$password@$ip:$port"
    else
        print_error "Не удалось запустить службу"
    fi
}

# Удаление подключения
remove_connection() {
    print_header "УДАЛЕНИЕ ПОДКЛЮЧЕНИЯ"
    
    if [[ ! -s $SERVICES_FILE ]]; then
        print_warning "Нет подключений для удаления"
        return
    fi
    
    echo "Выберите подключение для удаления:"
    local counter=1
    while IFS=':' read -r username port password service_name; do
        echo "$counter) $service_name (порт $port)"
        ((counter++))
    done < $SERVICES_FILE
    
    read -p "Номер подключения: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ]; then
        local line=$(sed -n "${choice}p" $SERVICES_FILE)
        if [[ -n "$line" ]]; then
            local username=$(echo $line | cut -d':' -f1)
            local port=$(echo $line | cut -d':' -f2)
            local service_name=$(echo $line | cut -d':' -f4)
            
            print_status "Удаление подключения '$service_name'..."
            
            # Остановка и удаление службы
            systemctl stop danted-$port > /dev/null 2>&1
            systemctl disable danted-$port > /dev/null 2>&1
            rm -f /etc/systemd/system/danted-$port.service
            rm -f /etc/danted-$port.conf
            systemctl daemon-reload
            
            # Удаление пользователя
            userdel $username > /dev/null 2>&1
            
            # Удаление правила брандмауэра
            ufw delete allow $port/tcp > /dev/null 2>&1
            
            # Удаление из списка
            sed -i "${choice}d" $SERVICES_FILE
            
            print_status "Подключение '$service_name' удалено"
        else
            print_error "Неверный номер подключения"
        fi
    else
        print_error "Неверный ввод"
    fi
}

# Полное удаление всех компонентов SOCKS5 прокси
uninstall_completely() {
    print_header "ПОЛНОЕ УДАЛЕНИЕ СИСТЕМЫ"
    print_warning "Это действие удалит ВСЕ подключения и компоненты SOCKS5 прокси!"
    print_warning "Восстановление будет невозможно!"
    echo ""
    
    read -p "Вы уверены, что хотите продолжить? (введите 'YES' для подтверждения): " confirm
    
    if [[ "$confirm" != "YES" ]]; then
        print_status "Операция отменена"
        return
    fi
    
    print_status "Начинаем полное удаление..."
    
    # Останавливаем и удаляем все SOCKS5 сервисы
    if [[ -s $SERVICES_FILE ]]; then
        print_status "Остановка и удаление всех SOCKS5 подключений..."
        while IFS=':' read -r username port password service_name; do
            print_status "Удаление подключения: $service_name (порт $port)"
            
            # Остановка службы
            systemctl stop danted-$port > /dev/null 2>&1
            systemctl disable danted-$port > /dev/null 2>&1
            
            # Удаление файлов службы
            rm -f /etc/systemd/system/danted-$port.service
            rm -f /etc/danted-$port.conf
            
            # Удаление пользователя
            userdel $username > /dev/null 2>&1
            
            # Удаление правил брандмауэра
            ufw delete allow $port/tcp > /dev/null 2>&1
            
        done < $SERVICES_FILE
        
        systemctl daemon-reload
    fi
    
    # Удаляем директорию конфигурации
    print_status "Удаление конфигурационных файлов..."
    rm -rf $CONFIG_DIR
    
    # Удаляем глобальную команду socks
    print_status "Удаление глобальной команды 'socks'..."
    rm -f /usr/local/bin/socks
    rm -f /usr/local/bin/socks-wrapper.sh
    
    # Очищаем bashrc от наших записей
    print_status "Очистка bashrc файлов..."
    
    # Удаляем из /etc/bash.bashrc
    if grep -q "socks-wrapper.sh" /etc/bash.bashrc 2>/dev/null; then
        sed -i '/# SOCKS5 Proxy Manager/d' /etc/bash.bashrc
        sed -i '/source \/usr\/local\/bin\/socks-wrapper.sh/d' /etc/bash.bashrc
        # Удаляем пустые строки в конце
        sed -i -e :a -e '/^\s*$/N; /^\s*\n$/ba' -e '/^\s*$/d' /etc/bash.bashrc
    fi
    
    # Удаляем из /root/.bashrc
    if grep -q "socks-wrapper.sh" /root/.bashrc 2>/dev/null; then
        sed -i '/# SOCKS5 Proxy Manager/d' /root/.bashrc
        sed -i '/source \/usr\/local\/bin\/socks-wrapper.sh/d' /root/.bashrc
        # Удаляем пустые строки в конце
        sed -i -e :a -e '/^\s*$/N; /^\s*\n$/ba' -e '/^\s*$/d' /root/.bashrc
    fi
    
    # Опционально: удаление dante-server (спрашиваем пользователя)
    echo ""
    read -p "Удалить пакет dante-server из системы? [y/N]: " remove_dante
    if [[ "$remove_dante" =~ ^[Yy]$ ]]; then
        print_status "Удаление пакета dante-server..."
        apt remove --purge -y dante-server > /dev/null 2>&1
        apt autoremove -y > /dev/null 2>&1
    fi
    
    # Очистка функций из текущего сеанса
    unset -f socks > /dev/null 2>&1
    
    print_status "Удаление завершено!"
    echo ""
    print_warning "Рекомендуется перезапустить терминал для полной очистки"
    print_warning "Команды 'socks' больше не доступны"
    echo ""
    
    # Предлагаем выйти из скрипта
    read -p "Выйти из скрипта? [Y/n]: " exit_choice
    if [[ ! "$exit_choice" =~ ^[Nn]$ ]]; then
        exit 0
    fi
}

# Главное меню
main_menu() {
    while true; do
        clear
        print_header "SOCKS5 PROXY MANAGER"
        echo "1) Показать все подключения"
        echo "2) Создать новое подключение"
        echo "3) Удалить подключение"
        echo "4) Полное удаление системы"
        echo "5) Выход"
        echo ""
        read -p "Выберите действие [1-5]: " choice
        
        case $choice in
            1) show_connections; read -p "Нажмите Enter для продолжения..." ;;
            2) create_connection; read -p "Нажмите Enter для продолжения..." ;;
            3) remove_connection; read -p "Нажмите Enter для продолжения..." ;;
            4) uninstall_completely; read -p "Нажмите Enter для продолжения..." ;;
            5) exit 0 ;;
            *) print_error "Неверный выбор"; sleep 2 ;;
        esac
    done
}

# Запускаем автоустановку
check_root
auto_install

# Основная логика
create_config_dir

# Проверка наличия dante-server
if ! command -v danted &> /dev/null; then
    print_status "Dante SOCKS server не найден. Устанавливаем..."
    install_dependencies
fi

# Запуск меню
if [[ $# -eq 0 ]]; then
    main_menu
else
    case $1 in
        --help) 
            echo -e "${BLUE}SOCKS5 Proxy Manager${NC}"
            echo "Использование: socks"
            echo ""
            echo "Команда запускает интерактивное меню для управления SOCKS5 прокси-серверами"
            ;;
        *)
            main_menu
            ;;
    esac
fi
