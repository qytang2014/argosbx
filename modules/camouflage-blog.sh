# camouflage-blog.sh: 伪装博客部署模块
# 每台机器按 /etc/machine-id 确定性随机选一个人设（16 选 1），
# 同一台机器 rep 不变，不同机器大概率不同，避免"所有站都叫陈默"的指纹。

# 人设池：AUTHOR|SITE_NAME|TAGLINE|BIO|AVATAR|AUTHOR_PINYIN
_camouflage_personas() {
  cat << 'PERSONA_EOF'
陈默|默记|陈默的技术笔记 —— Python、Linux 与 VPS 运维的实践记录|运维工程师，喜欢用 Python 写点自动化脚本，折腾 VPS 和开源软件。这个博客记录工作里踩过的坑和学到的东西，更新不定期。|默|chenmo
林晓|晓的技术笔记|林晓的技术笔记 —— 后端开发与效率工具|写 Java 和 Go 的后端程序员，偶尔写写 Python 脚本提高效率。这里记录一些开发和运维中的实战经验。|晓|linxiao
周远|远方笔记|周远的远方笔记 —— 全栈开发的学习记录|前后端都写一点的全栈工程师，对自建服务和开源项目感兴趣，博客用来整理学习笔记。|远|zhouyuan
苏晴|晴空下|苏晴的博客 —— 前端与 Linux 日常|前端工程师，喜欢捣鼓博客主题和静态网站，也记录一些 Linux 日常使用心得。|晴|suqing
陆明|明心录|陆明的明心录 —— DevOps 实践|专注自动化运维和 CI/CD，常用 Ansible 和 Docker，博客记录工作中的实践总结。|明|luming
沈静|静水流深|沈静的技术备忘录 —— 数据与 Python|和数据打交道，写 Python 做 ETL，也折腾服务器。这个博客是我的技术备忘录。|静|shenjing
高翔|翔宇技术志|高翔的技术志 —— 架构与运维思考|十多年 IT 老兵，经历过物理机、虚拟化到云原生，写点架构思考和运维经验。|翔|gaoxiang
何欣|欣欣向荣|何欣的博客 —— Python 学习之路|Python 重度用户，从爬虫到 Web 开发都写过，博客记录学习路径上的点滴。|欣|hexin
许磊|磊的网络笔记|许磊的博客 —— 网络与服务器|网络工程师，整天和交换机、路由器、防火墙打交道，也管几台 Linux 服务器。这里记一些排障和组网经验。|磊|xulei
赵雪|雪落无声|赵雪的安全手记 —— Linux 加固|做安全运维的，关注 Linux 加固、日志分析和入侵排查。博客分享一些实战中的安全经验。|雪|zhaoxue
钱峰|峰语|钱峰的数据库笔记 —— MySQL 与 PostgreSQL|DBA 一枚，日常和 MySQL、PostgreSQL 打交道，记录备份恢复、慢查询优化这些。|峰|qianfeng
孙丽|丽的测试小站|孙丽的博客 —— 测试与自动化|测试工程师，写 Python 做自动化测试，也研究 CI 流水线。分享测试方法和工具使用心得。|丽|sunli
李伟|伟大的航路|李伟的嵌入式笔记 —— Linux 与单片机|搞嵌入式的，用 Linux 做开发机，也玩树莓派和单片机。记录驱动调试和系统裁剪经验。|伟|liwei
吴刚|刚的云原生之路|吴刚的博客 —— Kubernetes 实践|云原生工程师，整天和 K8s、容器打交道。博客记录集群搭建和排障过程。|刚|wugang
郑凯|凯旋|郑凯的开源世界 —— 自建服务|开源爱好者，喜欢自建各种服务替代商业软件。博客分享 Docker 部署和 VPS 玩法。|凯|zhengkai
王芳|芳草地|王芳的技术写作 —— 文档与分享|技术写作者，把复杂的东西讲清楚是我的工作。博客整理学习笔记和工具评测。|芳|wangfang
PERSONA_EOF
}

# camouflage_pick_persona: 按机器 id 确定性选人设，设置 P_* 变量
camouflage_pick_persona() {
  local seed idx total
  seed=$(cat /etc/machine-id 2>/dev/null || hostname 2>/dev/null || echo "default")
  total=$(_camouflage_personas | wc -l)
  idx=$(echo "$seed" | cksum | awk -v n="$total" '{print $1 % n + 1}')
  local line
  line=$(_camouflage_personas | sed -n "${idx}p")
  P_AUTHOR=$(echo "$line" | cut -d'|' -f1)
  P_SITE_NAME=$(echo "$line" | cut -d'|' -f2)
  P_TAGLINE=$(echo "$line" | cut -d'|' -f3)
  P_BIO=$(echo "$line" | cut -d'|' -f4)
  P_AVATAR=$(echo "$line" | cut -d'|' -f5)
  P_AUTHOR_PINYIN=$(echo "$line" | cut -d'|' -f6)
}

# _camouflage_write <dest>: 从 stdin 读模板，替换占位符后写入 dest
_camouflage_write() {
  local _c
  _c=$(cat)
  _c="${_c//\{\{SITE_NAME\}\}/$P_SITE_NAME}"
  _c="${_c//\{\{AUTHOR\}\}/$P_AUTHOR}"
  _c="${_c//\{\{TAGLINE\}\}/$P_TAGLINE}"
  _c="${_c//\{\{BIO\}\}/$P_BIO}"
  _c="${_c//\{\{AVATAR\}\}/$P_AVATAR}"
  _c="${_c//\{\{AUTHOR_PINYIN\}\}/$P_AUTHOR_PINYIN}"
  printf '%s' "$_c" > "$1"
}

# deploy_camouflage_blog <webroot>: 部署伪装博客到 webroot
# 模板内容由 build.py 从 modules/camouflage/ 嵌入（见 CAMOUFLAGE_TEMPLATES 标记）
deploy_camouflage_blog() {
  local webroot="$1"
  [ -n "$webroot" ] || { echo "deploy_camouflage_blog: 需要 webroot 参数"; return 1; }
  camouflage_pick_persona
  mkdir -p "$webroot/posts"
  echo "伪装博客人设：$P_AUTHOR《$P_SITE_NAME》"
  # CAMOUFLAGE_TEMPLATES_START
  # （build.py 在此插入各模板文件的 _camouflage_write 调用）
  # CAMOUFLAGE_TEMPLATES_END
  chmod -R 755 "$webroot" 2>/dev/null || true
  find "$webroot" -type f -exec chmod 644 {} \; 2>/dev/null || true
  echo "伪装博客已部署到 $webroot"
}
