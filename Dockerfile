#build stage
FROM --platform=linux/amd64 public.ecr.aws/i1l4e9j0/golang:1.21-alpine3.17 AS builder
RUN apk add git
WORKDIR /go/src/app
COPY ../../ .
RUN go get -d -v ./...
RUN go build -o /go/bin/app cmd/app/main.go

#final stage
FROM public.ecr.aws/docker/library/alpine:3.17
RUN apk add ca-certificates
WORKDIR /myapp
COPY --from=builder /go/bin/app /myapp/app
COPY .env.development /myapp/.env
ENTRYPOINT /myapp/app
EXPOSE 80
