#!/bin/bash

# 闲鱼自动回复系统 Docker 部署脚本
# 两步部署：
# 1. push-image  构建并推送到 antake 的 Docker Hub 仓库
# 2. pull-start  拉取镜像并启动

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_NAME="xianyu-auto-reply"
COMPOSE_FILE="docker-compose.yml"
DEFAULT_IMAGE="${APP_IMAGE:-antake/xianyu-auto-reply:latest}"

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

resolve_image_name() {
    local image_name="$1"
    if [ -z "$image_name" ]; then
        image_name="$DEFAULT_IMAGE"
    fi
    echo "$image_name"
}

select_compose_file() {
    local use_cn="$1"
    if [[ "$use_cn" == "y" || "$use_cn" == "Y" ]]; then
        echo "docker-compose-cn.yml"
    else
        echo "$COMPOSE_FILE"
    fi
}

check_dependencies() {
    print_info "检查系统依赖..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi

    print_success "系统依赖检查通过"
}

init_config() {
    print_info "初始化配置文件..."

    if [ ! -f "entrypoint.sh" ]; then
        print_error "entrypoint.sh 文件不存在，Docker 容器将无法启动"
        exit 1
    fi

    if [ ! -f "global_config.yml" ]; then
        print_error "global_config.yml 配置文件不存在"
        exit 1
    fi

    mkdir -p data logs backups static/uploads/images
    print_success "已创建必要的目录"
}

build_image() {
    local image_name
    image_name=$(resolve_image_name "$1")

    print_info "构建 Docker 镜像: $image_name"
    echo "是否需要使用国内镜像(y/n): "
    read -r iscn

    local compose_file
    compose_file=$(select_compose_file "$iscn")

    APP_IMAGE="$image_name" docker-compose -f "$compose_file" build --no-cache
    print_success "镜像构建完成"
}

push_image() {
    local image_name
    image_name=$(resolve_image_name "$1")

    build_image "$image_name"
    print_info "推送镜像到 Docker Hub: $image_name"
    docker push "$image_name"
    print_success "镜像已推送: $image_name"
}

start_services() {
    local profile_arg="$1"
    local image_name
    image_name=$(resolve_image_name "$2")
    local profile=""

    if [ "$profile_arg" = "with-nginx" ]; then
        profile="--profile with-nginx"
        print_info "启动服务（包含 Nginx），使用镜像: $image_name"
    else
        print_info "启动基础服务，使用镜像: $image_name"
    fi

    APP_IMAGE="$image_name" docker-compose $profile up -d --no-build
    print_success "服务启动完成"

    print_info "等待服务就绪..."
    sleep 10

    if APP_IMAGE="$image_name" docker-compose ps | grep -q "Up"; then
        print_success "服务运行正常"
        show_access_info "$profile_arg"
    else
        print_error "服务启动失败"
        APP_IMAGE="$image_name" docker-compose logs
        exit 1
    fi
}

pull_and_start() {
    local image_name
    image_name=$(resolve_image_name "$1")

    print_info "拉取镜像: $image_name"
    APP_IMAGE="$image_name" docker-compose pull xianyu-app
    start_services "$2" "$image_name"
}

stop_services() {
    print_info "停止服务..."
    docker-compose down
    print_success "服务已停止"
}

restart_services() {
    print_info "重启服务..."
    docker-compose restart
    print_success "服务已重启"
}

show_logs() {
    local service="$1"
    if [ -z "$service" ]; then
        docker-compose logs -f
    else
        docker-compose logs -f "$service"
    fi
}

show_status() {
    print_info "服务状态:"
    docker-compose ps

    print_info "资源使用:"
    docker stats --no-stream $(docker-compose ps -q)
}

show_access_info() {
    local with_nginx="$1"

    echo ""
    print_success "部署完成"
    echo ""

    if [ "$with_nginx" = "with-nginx" ]; then
        echo "访问地址:"
        echo "  HTTP:  http://localhost"
        echo "  HTTPS: https://localhost"
    else
        echo "访问地址:"
        echo "  HTTP: http://localhost:8080"
    fi

    echo ""
    echo "默认登录信息:"
    echo "  用户名: admin"
    echo "  密码:   admin123"
    echo ""
}

health_check() {
    print_info "执行健康检查..."

    local url="http://localhost:8080/health"
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "$url" > /dev/null 2>&1; then
            print_success "健康检查通过"
            return 0
        fi

        print_info "等待服务就绪... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    print_error "健康检查失败"
    return 1
}

backup_data() {
    print_info "备份数据..."

    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    if [ -f "data/xianyu_data.db" ]; then
        cp data/xianyu_data.db "$backup_dir/"
        print_success "数据库备份完成"
    fi

    if [ -f ".env" ]; then
        cp .env "$backup_dir/"
    fi
    cp global_config.yml "$backup_dir/" 2>/dev/null || true

    print_success "数据备份完成: $backup_dir"
}

update_deployment() {
    local image_name
    image_name=$(resolve_image_name "$1")

    print_info "更新部署..."
    backup_data
    stop_services
    pull_and_start "$image_name"
    print_success "更新完成"
}

cleanup() {
    print_warning "这将删除所有容器、镜像和数据，确定要继续吗？(y/N)"
    read -r response

    if [[ "$response" =~ ^[Yy]$ ]]; then
        print_info "清理环境..."
        docker-compose down -v --rmi all
        rm -rf data logs backups
        print_success "环境清理完成"
    else
        print_info "取消清理操作"
    fi
}

show_help() {
    echo "闲鱼自动回复系统 Docker 部署脚本"
    echo ""
    echo "默认镜像: antake/xianyu-auto-reply:latest"
    echo ""
    echo "用法: $0 [命令] [参数]"
    echo ""
    echo "命令:"
    echo "  init                          初始化配置文件"
    echo "  build [image]                 仅本地构建镜像"
    echo "  push-image [image]            构建并推送镜像到 Docker Hub"
    echo "  start [with-nginx] [image]    使用本地已有镜像启动服务"
    echo "  pull-start [image] [with-nginx] 拉取镜像并启动服务"
    echo "  stop                          停止服务"
    echo "  restart                       重启服务"
    echo "  status                        查看服务状态"
    echo "  logs [service]                查看日志"
    echo "  health                        健康检查"
    echo "  backup                        备份数据"
    echo "  update [image]                拉取最新镜像并更新"
    echo "  cleanup                       清理环境"
    echo "  help                          显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 push-image"
    echo "  $0 push-image antake/xianyu-auto-reply:1.0"
    echo "  $0 pull-start"
    echo "  $0 pull-start antake/xianyu-auto-reply:1.0"
    echo ""
}

main() {
    case "$1" in
        "init")
            check_dependencies
            init_config
            ;;
        "build")
            check_dependencies
            init_config
            build_image "$2"
            ;;
        "push-image")
            check_dependencies
            init_config
            push_image "$2"
            ;;
        "start")
            check_dependencies
            init_config
            start_services "$2" "$3"
            ;;
        "pull-start")
            check_dependencies
            init_config
            pull_and_start "$2" "$3"
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            restart_services
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs "$2"
            ;;
        "health")
            health_check
            ;;
        "backup")
            backup_data
            ;;
        "update")
            check_dependencies
            init_config
            update_deployment "$2"
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        *)
            print_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
