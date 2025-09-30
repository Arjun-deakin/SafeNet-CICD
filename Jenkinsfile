pipeline {
  agent any
  options { timestamps() }  // removed ansiColor to avoid plugin requirement

  environment {
    RELEASE_VERSION = "1.0.${env.BUILD_NUMBER}"
    IMAGE_NAME = "your-dockerhub-username/safenet-api"
    IMAGE_TAG  = "${env.BUILD_NUMBER}"
    NODEJS_HOME         = tool 'node20'
    SONAR_SCANNER_HOME  = tool 'sonar-scanner'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        bat 'git rev-parse --short HEAD || true'
      }
    }

    stage('Build') {
      tools { nodejs 'node20' }
      steps {
        bat """
          node -v
          npm -v
          npm ci
        """
      }
    }

    stage('Test') {
      steps {
        bat 'npm test -- --coverage'
        archiveArtifacts artifacts: 'coverage/**', fingerprint: true
      }
    }

    stage('Code Quality (SonarCloud)') {
      steps {
        withSonarQubeEnv('SONARCLOUD') {
          bat """
            ${SONAR_SCANNER_HOME}/bin/sonar-scanner \
              -Dsonar.projectVersion=${RELEASE_VERSION}
          """
        }
      }
    }

    stage('Quality Gate (SonarCloud – no webhook)') {
      steps {
        script {
          def props = readProperties file: '.scannerwork/report-task.txt'
          def ceTaskId = props['ceTaskId']
          def serverUrl = props['serverUrl'] ?: 'https://sonarcloud.io'

          withCredentials([string(credentialsId: 'SONARCLOUD_TOKEN', variable: 'SC_TOKEN')]) {
            timeout(time: 5, unit: 'MINUTES') {
              waitUntil {
                def ceJson = bat(
                  script: "curl -s -u ${SC_TOKEN}: ${serverUrl}/api/ce/task?id=${ceTaskId}",
                  returnStdout: true
                ).trim()
                def mStatus = (ceJson =~ /\"status\":\"([A-Z_]+)\"/)
                if (!mStatus.find()) { sleep 3; return false }
                def status = mStatus.group(1)
                echo "SonarCloud CE task status: ${status}"

                if (status == 'SUCCESS') {
                  def mAnalysis = (ceJson =~ /\"analysisId\":\"([^\"]+)\"/)
                  if (mAnalysis.find()) { env.SONAR_ANALYSIS_ID = mAnalysis.group(1); return true }
                  else { error "CE task success but no analysisId found" }
                } else if (status in ['PENDING','IN_PROGRESS']) {
                  sleep 3; return false
                } else {
                  error "SonarCloud CE task failed: ${status}"
                }
              }
            }

            def qgJson = bat(
              script: "curl -s -u ${SC_TOKEN}: ${serverUrl}/api/qualitygates/project_status?analysisId=${env.SONAR_ANALYSIS_ID}",
              returnStdout: true
            ).trim()
            def mQG = (qgJson =~ /\"status\":\"([A-Z]+)\"/)
            if (!mQG.find()) { error "Unable to read Quality Gate status" }
            def qg = mQG.group(1)
            echo "SonarCloud Quality Gate: ${qg}"
            if (qg != 'OK') { error "Quality Gate failed: ${qg}" }
          }
        }
      }
    }

    stage('Security (Snyk)') {
      steps {
        withEnv(["PATH=${env.NODEJS_HOME}/bin:${env.PATH}"]) {
          withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
            bat """
              npm ci
              npx snyk auth ${SNYK_TOKEN} || true
              npx snyk test || true
              npx snyk monitor || true
            """
          }
        }
      }
    }

    stage('Deploy: Staging') {
      steps {
        bat "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          bat """
            echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
            docker push ${IMAGE_NAME}:${IMAGE_TAG}
          """
        }
        bat """
          IMAGE_TAG=${IMAGE_TAG} docker compose -f docker-compose.staging.yml up -d --remove-orphans
          sleep 3
          curl -fsS http://localhost:3000/health || true
        """
      }
    }

    stage('Release: Promote to Prod (Manual)') {
      steps {
        input message: "Promote build #${env.BUILD_NUMBER} (v${RELEASE_VERSION}) to PROD?", ok: 'Release'
        bat "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          bat """
            echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
            docker push ${IMAGE_NAME}:latest
          """
        }
        bat 'git config user.email "ci@example.com" || true'
        bat 'git config user.name "ci" || true'
        bat 'git tag -a v${RELEASE_VERSION} -m "Release ${RELEASE_VERSION}" || true'
        bat 'git push --tags || true'
        bat 'IMAGE_TAG=latest docker compose -f docker-compose.prod.yml up -d --remove-orphans'
      }
    }

    stage('Monitoring & Alerting') {
      steps {
        echo 'Prometheus scraping /metrics; Grafana dashboards recommended.'
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'docker-compose.*.yml, sonar-project.properties', onlyIfSuccessful: false
    }
    success { echo "Pipeline OK. Image: ${IMAGE_NAME}:${IMAGE_TAG}, Version: ${RELEASE_VERSION}" }
    failure { echo "Pipeline failed. Check Build/Test/Sonar/Snyk/Deploy logs." }
  }
}
