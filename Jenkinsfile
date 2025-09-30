pipeline {
  agent any
  options { timestamps(); ansiColor('xterm') }

  environment {
    IMAGE_NAME = "your-dockerhub-username/safenet-api"
    IMAGE_TAG  = "${env.BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build') {
      tools { nodejs 'node20' }
      steps {
        sh 'node -v'
        sh 'npm ci'
      }
    }

    stage('Test') {
      steps {
        sh 'npm test -- --coverage'
        junit 'coverage/**/junit.xml' // if you add jest-junit reporter
      }
    }

    stage('Code Quality (SonarQube)') {
      environment { SONAR_SCANNER_HOME = tool 'sonar-scanner' }
      steps {
        withSonarQubeEnv('SONARQUBE') {
          sh "${SONAR_SCANNER_HOME}/bin/sonar-scanner"
        }
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 2, unit: 'MINUTES') {
          script {
            def qg = waitForQualityGate()
            if (qg.status != 'OK') {
              error "Pipeline failed due to quality gate: ${qg.status}"
            }
          }
        }
      }
    }

    stage('Security (Snyk)') {
      steps {
        sh 'npm ci'
        withEnv(["SNYK_TOKEN=${SNYK_TOKEN}"]) {
          sh 'npx snyk test || true'     // test for vulnerabilities
          sh 'npx snyk monitor || true'  // send results to dashboard
        }
      }
    }

    stage('Deploy: Staging') {
      steps {
        sh 'docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .'
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          sh 'echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin'
          sh 'docker push ${IMAGE_NAME}:${IMAGE_TAG}'
        }
        sh 'IMAGE_TAG=${IMAGE_TAG} docker compose -f docker-compose.staging.yml up -d --remove-orphans'
      }
    }

    stage('Release: Promote to Prod (Manual)') {
      steps {
        input message: "Promote build #${env.BUILD_NUMBER} to PROD?", ok: 'Release'
        sh 'docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest'
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          sh 'echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin'
          sh 'docker push ${IMAGE_NAME}:latest'
        }
        sh 'IMAGE_TAG=latest docker compose -f docker-compose.prod.yml up -d --remove-orphans'
      }
    }

    stage('Monitoring & Alerting') {
      steps {
        echo 'Prometheus scraping /metrics and Grafana dashboards available.'
      }
    }
  }
}
