# Below resource is to create public key

resource "tls_private_key" "sskeygen_execution" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Below are the aws key pair
resource "aws_key_pair" "prometheus_key_pair" {
  depends_on = ["tls_private_key.sskeygen_execution"]
  key_name   = "${var.aws_public_key_name}"
  public_key = "${tls_private_key.sskeygen_execution.public_key_openssh}"
}

# prometheus instance
resource "aws_instance" "prometheus_instance" {
  ami               = "${lookup(var.aws_amis, var.aws_region)}"
  instance_type     = "${var.aws_instance_type}"
  availability_zone = "${var.aws_availability_zone}"
  key_name               = "${aws_key_pair.prometheus_key_pair.id}"
  #vpc_security_group_ids = ["${aws_security_group.prometheus_security_group.id}"]
  #subnet_id              = "${aws_subnet.prometheus_subnet.id}"

  connection {
    user        = "ubuntu"
    host = self.public_ip
    private_key = "${tls_private_key.sskeygen_execution.private_key_pem}"
  }

# Copy the prometheus file to instance
  provisioner "file" {
    source      = "./prometheus.yml"
    destination = "/tmp/prometheus.yml" 
  }

# Install docker in the ubuntu
  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install docker.io -y",
      "sudo mkdir /prometheus-data",
      "sudo cp /tmp/prometheus.yml /prometheus-data/.",
      "sudo docker run -d -p 9090:9090 --name=prometheus -v /prometheus-data/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus",
      "sudo docker run -d -p 3000:3000 --name=grafana grafana/grafana",
      "sudo docker run -d -p 3100:3100 --name=loki grafana/loki",
      "sudo docker run -d --name tempo -v /opt/tempo/tempo.yaml:/bitnami/grafana-tempo/conf/tempo.yaml -p 3200:3200 -p 14268:14268 -p 9095:9095 -p 4318:4318 -p 9411:9411 -p 4317:4317 bitnami/grafana-tempo:latest"
    ]
  }

  provisioner "local-exec" {
    command = "echo '${tls_private_key.sskeygen_execution.private_key_pem}' >> ${aws_key_pair.prometheus_key_pair.id}.pem ; chmod 400 ${aws_key_pair.prometheus_key_pair.id}.pem"
  }

  tags = {
    Name = "${var.name}_instance"
    Environment = "${var.env}"
  }
}
