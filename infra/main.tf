terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.29.0"
    }
  }
}

provider "google" {
  project     = var.project_id
  region      = var.region
  credentials = file(var.credentials)
}

resource "google_storage_bucket" "data-bucket" {
  name          = var.data_bucket
  location      = var.location
  force_destroy = true
  storage_class = var.gcs_storage_class

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

resource "google_storage_bucket" "code-bucket" {
  name          = var.code_bucket
  location      = var.location
  force_destroy = true
  storage_class = var.gcs_storage_class

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

resource "google_storage_bucket_object" "data-download-script" {
  name   = "download_data.py"
  bucket = google_storage_bucket.code-bucket.name
  source = "../data_ingestion/download_data.py"
}

# Read in script file
locals {
  script_content = file("./Install_docker.sh")
  gsc_service_acct = file("../.google/credentials/google-credentials.json")
  gsc_service_acct_base64 = base64encode(file("../.google/credentials/google-credentials.json"))
}

resource "google_compute_instance" "vm_instance" {
  name         = "ubuntu-airflow"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      #Find these in gcloud sdk by running gcloud compute machine-types|grep <what you are looking for e.g. ubuntu>
      image = "ubuntu-2004-focal-v20240307b"
    }
  }

  network_interface {
    network = "default"
    access_config{

    }
  }

# Use the content of the script file in the metadata_startup_script
metadata = {
  ssh-keys = "${var.user}:${file(var.ssh_key_file)}"
  user-data = <<-EOF
    #!/bin/bash
    
    sudo apt-get update
    echo '${local.script_content}' > /tmp/install_docker.sh
    chmod +x /tmp/install_docker.sh
    bash /tmp/install_docker.sh

    sudo mkdir -p /home/${var.user}/.google/credentials
    chmod -R 755 /home/${var.user}/.google


    cd /home/${var.user} 
    git clone https://github.com/BastienWinant/airflow-docker-compose2025.git

    sudo mkdir -p /home/${var.user}/airflow-docker-compose2025/.google/credentials
    chmod -R 755 /home/${var.user}/airflow-docker-compose2025/.google
    
    echo '${local.gsc_service_acct}' > /home/${var.user}/airflow-docker-compose2025/.google/credentials/google_credentials.json
    cd ./airflow-docker-compose2025

    
    echo "This is a file created on $(date)" > /home/${var.user}/"$(date +"%Y-%m-%d_%H-%M-%S").txt"

    sudo mkdir -p ./dags ./logs ./plugins ./config
    sudo chown -R 1001:1001 ./dags ./logs ./plugins ./config
    chmod -R 775 ./dags ./logs ./plugins ./config
    sudo usermod -aG docker ${var.user}
    newgrp docker
    docker compose up airflow-init

    sleep 30
    docker compose up

  EOF
    }
}

output "public_ip" {
  value = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
}
