pipeline {
  agent any
  options { timestamps(); ansiColor('xterm') }

  environment {
    IMAGE_NAME = "your-dockerhub-username/safenet-api"
    IMAGE_TAG  = "${env.BUILD_NUMBER}"               // immutable build id
    // Semantic-ish release version you want to appear in Sonar
    RELEASE_VERSION = "1.0.${env.BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') { steps { checkout scm } }

    stage('Build') {
      tools { nodejs 'node20' }
      steps { sh 'npm ci' }
    }

    stage('Test') {
      steps {
        sh 'npm test -- --coverage'
        // add jest-junit if you want JUnit in Jenkins:
        // junit 'reports/junit.xml'
      }
    }

    stage('Code Quality (SonarQube)') {
      environment { SONAR_SCANNER_HOME = tool 'sonar-scanner' }
      steps {
        withSonarQubeEnv('SONARQUBE') {
          // Pass the version so Sonar can compare *since previous version*
          sh """
            ${SONAR_SCANNER_HOME}/bin/sonar-scanner \
              -Dsonar.projectVersion=${RELEASE_VERSION}
          """
        }
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 3, unit: 'MINUTES') {
          script {
            def qg = waitForQualityGate()
            if (qg.status != 'OK') error "Quality gate failed: ${qg.status}"
          }
        }
      }
    }

    stage('Security (Snyk)') {
      steps {
        withEnv(["SNYK_TOKEN=${SNYK_TOKEN}"]) {
          sh 'npx snyk test || true'
          sh 'npx snyk monitor || true'
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
        // tag docker & git with the *same* version passed to Sonar
        sh 'docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest'
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          sh 'echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin'
          sh 'docker push ${IMAGE_NAME}:latest'
        }
        sh 'git tag -a v${RELEASE_VERSION} -m "Release ${RELEASE_VERSION}" || true'
        sh 'git push --tags || true'
        sh 'IMAGE_TAG=latest docker compose -f docker-compose.prod.yml up -d --remove-orphans'
      }
    }
  }
}
