# Private argosbx container image (qytang2014/argosbx).
# Build context is this directory (container/nodejs), so the image always
# uses the COMMITTED generated start.sh (built by build/build.py, with
# cert / egress / domain-address modules), not the upstream original.
# index.js runs `bash start.sh` on container start; kernels (xray /
# sing-box) are downloaded at runtime by start.sh, they are NOT baked in.
# The image must be PUBLIC: sapsbx.sh runs `cf push --docker-image` with
# no Docker credentials, so SAP Cloud Foundry cannot pull a private image.
FROM node:20-slim
WORKDIR /app
COPY package.json index.js start.sh ./
RUN npm install --omit=dev && chmod +x start.sh
EXPOSE 3000
CMD ["node", "index.js"]
