# 多阶段构建优化版 Dockerfile
# 第一阶段：构建环境
FROM debian:bullseye as builder

# 安装构建依赖 - 合并apt-get命令减少镜像层
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install \
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

# 克隆源码 - 使用WORKDIR减少路径硬编码
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
RUN ./configure --prefix=/opt/freeswitch  # 使用专用目录避免污染系统
RUN make -j$(nproc) && make install

# 第二阶段：运行时环境
FROM debian:bullseye-slim

# 安装运行时依赖 - 添加缺失的icu库和ca-certificates
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install \
    libssl1.1 libpcre3 libedit2 libsqlite3-0 libcurl4 \
    libogg0 libspeex1 libspeexdsp1 libldns2 libavformat58 \
    libswscale5 libavresample4 liblua5.2-0 libopus0 \
    libpq5 libsndfile1 libflac8 libvorbis0a libshout3 \
    libmpg123-0 libmp3lame0 libicu67 ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制构建结果 - 使用专用安装目录
COPY --from=builder /opt/freeswitch /opt/freeswitch

# 创建专用用户
RUN groupadd freeswitch && \
    useradd -r -g freeswitch -d /opt/freeswitch freeswitch

# 设置目录权限
RUN mkdir -p /var/log/freeswitch /var/run/freeswitch && \
    chown -R freeswitch:freeswitch /opt/freeswitch /var/log/freeswitch /var/run/freeswitch

# 设置环境变量
ENV PATH="/opt/freeswitch/bin:${PATH}"

# 设置工作目录
WORKDIR /opt/freeswitch

# 切换非特权用户
USER freeswitch

# 启动命令 - 添加非前台参数
CMD ["freeswitch", "-nonat"]
