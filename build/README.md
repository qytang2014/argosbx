# 构建说明（第 1 阶段：argosbx.sh 分层）

## 不要手改的文件
- `argosbx.sh`（根目录）：**构建产物**，由 `build/build.py` 生成，手改下次构建会被覆盖。
- `upstream/argosbx.sh`：**上游原版**，现在是 `yonggekkk/argosbx main@08c5416`，不要在里面加私有内容。

## 可以改的文件
- `modules/cert.sh`：证书 / Caddy / acme 功能。
- `modules/egress.sh`：动态出口功能。
- `modules/cert-main.sh`：主流程里证书那一段的替换块（上游原来是调用外部 acme-yg 脚本）。
- `build/build.py`：锚点替换清单。加新功能时，先加模块文件，再在清单里加锚点，不要直接改生成文件。

## 构建
```
python3 build/build.py
bash -n argosbx.sh
```

## 上游同步（以后）
1. 把新上游文件替换 `upstream/argosbx.sh`。
2. 跑 `python3 build/build.py`。
3. 如果构建报某个锚点缺失，说明上游改了那一行，只修 `build/build.py` 里那一个锚点，不要全文件合并。
4. 跑测试：`bash -n`、出口隔离测试、证书逻辑测试，再推。

## 加新功能（以后）
1. 新建 `modules/<功能>.sh`，只写自己的函数和变量。
2. 在 `build/build.py` 里加插入锚点和钩子（如果需要）。
3. 跑构建和测试，不要直接改 `argosbx.sh`，不要改 `upstream/argosbx.sh`。

## 本阶段不做的事
- `index.html`、容器版 `start.sh` 不动。
- 上游代码本身不做去重 / 优化，那会再次破坏上游同步。构建产物大小和原来基本一致，变小的是每个源文件的规模和改动范围。
