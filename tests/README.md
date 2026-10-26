# 测试说明

## 跑全部测试（推荐）
```
bash tests/run_all.sh
```
顺序是：先构建，再测构建同步、语法、出口、证书、页面、上游纯净。任何一步失败就停，不会继续跑后面的测试。

## 单独跑某一个
```
bash tests/test_build.sh    # 生成文件是否和源文件同步 + bash -n
bash tests/test_egress.sh   # 出口模块隔离测试：不限节点、Reality、bind IP、分流规则、无配置时零改动
bash tests/test_cert.sh     # 证书函数隔离测试：certsrc、certmode、write_caddyfile（不写真实 /etc/caddy）
python3 tests/test_index.py # 页面：私有 UI/JS 都在、脚本 URL 指向私有仓库、optIds 都有对应元素、上游文件未被改
```

## 测试原则
- 不联网、不装包、不写真实系统目录（`/etc/caddy` 用临时目录替换测试）。
- 不跑真实安装、不发证、不启动 sing-box / xray，只测生成逻辑。
- 证书和出口的完整安装效果，仍需在目标机器上第一次使用时看一次输出确认。
