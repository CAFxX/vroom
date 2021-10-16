FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu-21.04
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update -y && \
    apt-get install -y git make gcc gcc-riscv64-linux-gnu device-tree-compiler iverilog
