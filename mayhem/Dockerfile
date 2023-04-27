FROM ghcr.io/evanrichter/cargo-fuzz as builder

ADD . /fastqr
WORKDIR /fastqr/fuzz
RUN cargo +nightly fuzz build 

FROM debian:bookworm
COPY --from=builder /fastqr/fuzz/target/x86_64-unknown-linux-gnu/release/fastqr_fuzz /