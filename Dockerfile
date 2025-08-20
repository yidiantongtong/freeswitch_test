# 多阶段构建优化版 Dockerfile
# 第一阶段：构建环境
FROM debian:bullseye as builder

# 使用阿里云镜像源并安装构建依赖
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install --no-install-recommends \
    git build-essential cmake automake autoconf libtool pkg-config \
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev \
    libexpat1-dev libgdbm-dev bison erlang-dev libtpl-dev libtiff5-dev \
    uuid-dev libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev \
    nasm libogg-dev libspeex-dev libspeexdsp-dev libldns-dev python3-dev \
    libavformat-dev libswscale-dev libavresample-dev liblua5.2-dev \
    libopus-dev libpq-dev libsndfile1-dev libflac-dev libvorbis-dev \
    libshout3-dev libmpg123-dev libmp3lame-dev libpcre2-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 克隆源码 (使用浅克隆减少大小)
WORKDIR /usr/src
RUN git clone --depth 1 https://github.com/signalwire/freeswitch
RUN mkdir libs && cd libs && \
    git clone --depth 1 https://github.com/signalwire/libks && \
    git clone --depth 1 https://github.com/freeswitch/sofia-sip && \
    git clone --depth 1 https://github.com/freeswitch/spandsp && \
    git clone --depth 1 https://github.com/signalwire/signalwire-c

# 构建依赖库
WORKDIR /usr/src/libs/libks
RUN cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install

WORKDIR /usr/src/libs/sofia-sip
RUN ./bootstrap.sh && \
    ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no \
    --without-doxygen --disable-stun --prefix=/usr && \
    make -j$(nproc) && make install

WORKDIR /usr/src/libs/spandsp
RUN ./bootstrap.sh && \
    ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && \
    make -j$(nproc) && make install

WORKDIR /usr/src/libs/signalwire-c
RUN PKG_CONFIG_PATH=/usr/lib/pkgconfig cmake . -DCMAKE_INSTALL_PREFIX=/usr && make install

# 构建 FreeSWITCH
WORKDIR /usr/src/freeswitch
RUN ./bootstrap.sh -j
RUN ./configure --prefix=/opt/freeswitch
RUN make -j$(nproc) && make install

# 第二阶段：运行时环境
FROM debian:bullseye-slim

# 设置时区
ENV TZ=UTC

# 使用阿里云镜像源并安装运行时依赖
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list && \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install --no-install-recommends \
    # 核心依赖
    libssl1.1 libpcre3 libedit2 libsqlite3-0 libcurl4 \
    # 音频处理
    libogg0 libspeex1 libspeexdsp1 libldns2 libopus0 \
    libsndfile1 libflac8 libvorbis0a libmpg123-0 libmp3lame0 \
    # 视频处理
    libavformat58 libswscale5 libavresample4 \
    # 数据库和其他
    libpq5 liblua5.2-0 libicu67 ca-certificates libshout3 \
    # 修复libldns2找不到的问题
    libldns2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制构建结果
COPY --from=builder /opt/freeswitch /opt/freeswitch

# 创建专用用户
RUN groupadd freeswitch && \
    useradd -r -g freeswitch -d /opt/freeswitch freeswitch

# 创建必要目录并设置权限
RUN mkdir -p /var/log/freeswitch /var/run/freeswitch && \
    chown -R freeswitch:freeswitch /opt/freeswitch /var/log/freeswitch /var/run/freeswitch

# 设置环境变量
ENV PATH="/opt/freeswitch/bin:${PATH}"

# 设置工作目录
WORKDIR /opt/freeswitch

# 切换非特权用户
USER freeswitch

# 启动命令
CMD ["freeswitch", "-nonat"]
