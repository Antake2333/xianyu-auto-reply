@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

REM 闲鱼自动回复系统 Docker 部署脚本 (Windows)
REM 默认使用 Docker Hub: antake/xianyu-auto-reply:latest

title 闲鱼自动回复系统 Docker 部署

set "DEFAULT_IMAGE=antake/xianyu-auto-reply:latest"
if "%APP_IMAGE%"=="" set "APP_IMAGE=%DEFAULT_IMAGE%"

set "INFO_PREFIX=[INFO]"
set "SUCCESS_PREFIX=[SUCCESS]"
set "WARNING_PREFIX=[WARNING]"
set "ERROR_PREFIX=[ERROR]"

echo %INFO_PREFIX% 检查系统依赖...
where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo %ERROR_PREFIX% Docker 未安装，请先安装 Docker Desktop
    pause
    exit /b 1
)

where docker-compose >nul 2>&1
if %errorlevel% neq 0 (
    echo %ERROR_PREFIX% Docker Compose 未安装，请先安装 Docker Compose
    pause
    exit /b 1
)
echo %SUCCESS_PREFIX% 系统依赖检查通过

if not exist "entrypoint.sh" (
    echo %ERROR_PREFIX% entrypoint.sh 文件不存在
    pause
    exit /b 1
)

if not exist "global_config.yml" (
    echo %ERROR_PREFIX% global_config.yml 配置文件不存在
    pause
    exit /b 1
)

if not exist "data" mkdir data
if not exist "logs" mkdir logs
if not exist "backups" mkdir backups
if not exist "static\uploads\images" mkdir static\uploads\images

if "%1"=="" goto show_help
if "%1"=="help" goto show_help
if "%1"=="build" goto build_image
if "%1"=="push-image" goto push_image
if "%1"=="start" goto start_services
if "%1"=="pull-start" goto pull_start
if "%1"=="stop" goto stop_services
if "%1"=="restart" goto restart_services
if "%1"=="status" goto show_status
if "%1"=="logs" goto show_logs
if "%1"=="cleanup" goto cleanup
goto unknown_command

:build_image
if not "%2"=="" set "APP_IMAGE=%2"
echo %INFO_PREFIX% 构建 Docker 镜像: %APP_IMAGE%
set /p use_cn="是否使用国内镜像源？(y/n): "
if /i "!use_cn!"=="y" (
    docker-compose -f docker-compose-cn.yml build --no-cache
) else (
    docker-compose build --no-cache
)
if %errorlevel% neq 0 (
    echo %ERROR_PREFIX% 镜像构建失败
    pause
    exit /b 1
)
echo %SUCCESS_PREFIX% 镜像构建完成
goto end

:push_image
if not "%2"=="" set "APP_IMAGE=%2"
call :build_image %APP_IMAGE%
docker push %APP_IMAGE%
if %errorlevel% neq 0 (
    echo %ERROR_PREFIX% 镜像推送失败
    pause
    exit /b 1
)
echo %SUCCESS_PREFIX% 镜像已推送: %APP_IMAGE%
goto end

:start_services
if not "%3"=="" set "APP_IMAGE=%3"
echo %INFO_PREFIX% 启动服务，使用镜像: %APP_IMAGE%
if /i "%2"=="with-nginx" (
    docker-compose --profile with-nginx up -d --no-build
) else (
    docker-compose up -d --no-build
)
if %errorlevel% neq 0 (
    echo %ERROR_PREFIX% 服务启动失败
    docker-compose logs
    pause
    exit /b 1
)
echo %SUCCESS_PREFIX% 服务启动完成
goto end

:pull_start
if not "%2"=="" set "APP_IMAGE=%2"
echo %INFO_PREFIX% 拉取镜像: %APP_IMAGE%
docker-compose pull xianyu-app
if %errorlevel% neq 0 (
    echo %ERROR_PREFIX% 镜像拉取失败
    pause
    exit /b 1
)
call :start_services %1 %3 %APP_IMAGE%
goto end

:stop_services
docker-compose down
echo %SUCCESS_PREFIX% 服务已停止
goto end

:restart_services
docker-compose restart
echo %SUCCESS_PREFIX% 服务已重启
goto end

:show_status
docker-compose ps
goto end

:show_logs
if "%2"=="" (
    docker-compose logs -f
) else (
    docker-compose logs -f %2
)
goto end

:cleanup
echo %WARNING_PREFIX% 这将删除所有容器、镜像和数据，确定要继续吗？
set /p confirm="请输入 y 确认: "
if /i "!confirm!"=="y" (
    docker-compose down -v --rmi all
    rmdir /s /q data logs backups 2>nul
    echo %SUCCESS_PREFIX% 环境清理完成
)
goto end

:show_help
echo 闲鱼自动回复系统 Docker 部署脚本
echo.
echo 默认镜像: antake/xianyu-auto-reply:latest
echo.
echo 用法:
echo   docker-deploy.bat push-image
echo   docker-deploy.bat push-image antake/xianyu-auto-reply:1.0
echo   docker-deploy.bat pull-start
echo   docker-deploy.bat pull-start antake/xianyu-auto-reply:1.0
echo.
goto end

:unknown_command
echo %ERROR_PREFIX% 未知命令: %1
goto show_help

:end
