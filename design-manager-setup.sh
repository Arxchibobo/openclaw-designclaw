#!/bin/bash
# ============================================================
# MyShellDesignManager - Nginx 反向代理配置脚本
# 
# 目的：将 DesignManager 应用（端口 9969）通过 nginx 暴露出来
# 服务器：103.207.68.10
# 
# 使用方法：
#   chmod +x design-manager-setup.sh
#   sudo bash design-manager-setup.sh
# ============================================================

set -e

echo "🚀 开始配置 MyShellDesignManager Nginx 反向代理..."

# ---- Step 1: 检查 PM2 应用是否在运行 ----
echo ""
echo "📋 Step 1: 检查应用状态..."
if command -v pm2 &> /dev/null; then
    pm2 list
    echo ""
    # 检查 9969 端口
    if ss -tlnp | grep -q ":9969"; then
        echo "✅ 端口 9969 已在监听"
    else
        echo "⚠️  端口 9969 未在监听，尝试启动应用..."
        cd /root/MyShellDesignManager
        pm2 start ecosystem.config.cjs
        sleep 3
        if ss -tlnp | grep -q ":9969"; then
            echo "✅ 应用启动成功"
        else
            echo "❌ 应用启动失败，请手动检查"
            exit 1
        fi
    fi
else
    echo "⚠️  PM2 未安装，检查端口 9969..."
    if ss -tlnp | grep -q ":9969"; then
        echo "✅ 端口 9969 已在监听"
    else
        echo "❌ 端口 9969 未在监听，且 PM2 未安装"
        echo "   请先手动启动应用：cd /root/MyShellDesignManager && node server/index.js"
        exit 1
    fi
fi

# ---- Step 2: 创建 Nginx 配置 ----
echo ""
echo "📋 Step 2: 创建 Nginx 配置..."

NGINX_CONF="/etc/nginx/conf.d/design-manager.conf"

cat > "$NGINX_CONF" << 'EOF'
# MyShellDesignManager - 反向代理配置
# 端口 9969 -> 通过 /design-manager/ 路径访问
# 或者直接用 9970 端口访问（二选一）

# 方案A：独立端口（推荐，不影响现有 443 服务）
server {
    listen 9970;
    server_name _;

    # 前端页面
    location / {
        proxy_pass http://127.0.0.1:9969;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket 支持（如果需要）
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 超时设置（大文件上传）
        proxy_connect_timeout 60s;
        proxy_send_timeout 600s;
        proxy_read_timeout 600s;
        client_max_body_size 500M;
    }
}
EOF

echo "✅ Nginx 配置已写入: $NGINX_CONF"

# ---- Step 3: 测试并重载 Nginx ----
echo ""
echo "📋 Step 3: 测试并重载 Nginx..."

nginx -t
if [ $? -eq 0 ]; then
    nginx -s reload
    echo "✅ Nginx 重载成功"
else
    echo "❌ Nginx 配置测试失败，请检查"
    exit 1
fi

# ---- Step 4: 开放防火墙端口 ----
echo ""
echo "📋 Step 4: 检查防火墙..."

# UFW
if command -v ufw &> /dev/null; then
    ufw allow 9970/tcp
    echo "✅ UFW 已开放 9970 端口"
fi

# firewalld
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=9970/tcp
    firewall-cmd --reload
    echo "✅ firewalld 已开放 9970 端口"
fi

# iptables (fallback)
if command -v iptables &> /dev/null && ! command -v ufw &> /dev/null && ! command -v firewall-cmd &> /dev/null; then
    iptables -A INPUT -p tcp --dport 9970 -j ACCEPT
    echo "✅ iptables 已开放 9970 端口"
    echo "⚠️  注意：iptables 规则重启后失效，建议用 iptables-save 持久化"
fi

# ---- Step 5: 验证 ----
echo ""
echo "📋 Step 5: 验证..."
sleep 2

HEALTH=$(curl -s --connect-timeout 5 http://127.0.0.1:9970/health 2>&1)
if echo "$HEALTH" | grep -q '"status":"ok"'; then
    echo "✅ 验证通过！健康检查返回: $HEALTH"
else
    echo "⚠️  健康检查返回: $HEALTH"
    echo "   如果显示为空，可能需要等待几秒后手动测试："
    echo "   curl http://127.0.0.1:9970/health"
fi

echo ""
echo "============================================================"
echo "🎉 配置完成！"
echo ""
echo "访问地址："
echo "  前端页面:  http://103.207.68.10:9970/"
echo "  健康检查:  http://103.207.68.10:9970/health"
echo "  API 接口:  http://103.207.68.10:9970/api/"
echo ""
echo "超级管理员登录："
echo "  用户名: MyShell"
echo "  密码:   MyShell@Bobo"
echo ""
echo "API 示例："
echo "  curl http://103.207.68.10:9970/api/users"
echo "  curl http://103.207.68.10:9970/api/tasks"
echo "  curl http://103.207.68.10:9970/api/assignments"
echo "============================================================"
