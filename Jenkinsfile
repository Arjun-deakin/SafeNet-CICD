pipeline {
  agent any
  options { timestamps() }

  environment {
    RELEASE_VERSION     = "1.0.${env.BUILD_NUMBER}"
    IMAGE_NAME          = "your-dockerhub-username/safenet-api"
    IMAGE_TAG           = "${env.BUILD_NUMBER}"

    // Tool names must match your "Global Tool Configuration"
    NODEJS_HOME         = tool 'node20'
    SONAR_SCANNER_HOME  = tool 'sonar-scanner'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        bat 'git rev-parse --short HEAD || ver > nul'
      }
    }

    stage('Build') {
      steps {
        withEnv(["PATH=${env.NODEJS_HOME}\\bin;${env.PATH}"]) {
          bat """
            node -v
            npm -v
            npm ci
          """
        }
      }
    }

    stage('Test') {
      steps {
        withEnv(["PATH=${env.NODEJS_HOME}\\bin;${env.PATH}"]) {
          // npm test will resolve local jest from node_modules/.bin
          bat 'npm test -- --coverage'
        }
        archiveArtifacts artifacts: 'coverage/**', fingerprint: true
      }
    }

    stage('Code Quality (SonarCloud)') {
      steps {
        withSonarQubeEnv('SONARCLOUD') {
          // On Windows, call the .bat wrapper
          bat "\"%SONAR_SCANNER_HOME%\\bin\\sonar-scanner.bat\" -Dsonar.projectVersion=${RELEASE_VERSION}"
        }
      }
    }

    stage('Quality Gate (SonarCloud – no webhook)') {
      steps {
        script {
          // Read task file produced by the scanner
          def props = readProperties file: '.scannerwork/report-task.txt'
          def ceTaskId = props['ceTaskId']
          def serverUrl = props['serverUrl'] ?: 'https://sonarcloud.io'

          withCredentials([string(credentialsId: 'SONARCLOUD_TOKEN', variable: 'SC_TOKEN')]) {
            timeout(time: 5, unit: 'MINUTES') {
              waitUntil {
                // Windows has curl available on recent versions; otherwise install it or use PowerShell Invoke-WebRequest
                def ceJson = bat(
                  script: "curl -s -u %SC_TOKEN%: ${serverUrl}/api/ce/task?id=${ceTaskId}",
                  returnStdout: true
                ).trim()

                def mStatus = (ceJson =~ /\"status\":\"([A-Z_]+)\"/)
                if (!mStatus.find()) { sleep 3; return false }
                def status = mStatus.group(1)
                echo "SonarCloud CE task status: ${status}"

                if (status == 'SUCCESS') {
                  def mAnalysis = (ceJson =~ /\"analysisId\":\"([^\"]+)\"/)
                  if (mAnalysis.find()) { env.SONAR_ANALYSIS_ID = mAnalysis.group(1); return true }
                  error "CE task success but no analysisId found"
                } else if (status in ['PENDING','IN_PROGRESS']) {
                  sleep 3; return false
                } else {
                  error "SonarCloud CE task failed: ${status}"
                }
              }
            }

            def qgJson = bat(
              script: "curl -s -u %SC_TOKEN%: ${serverUrl}/api/qualitygates/project_status?analysisId=${env.SONAR_ANALYSIS_ID}",
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
        withEnv(["PATH=${env.NODEJS_HOME}\\bin;${env.PATH}"]) {
          withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
            bat """
              npm ci
              npx snyk auth %SNYK_TOKEN% || ver > nul
              npx snyk test || ver > nul
              npx snyk monitor || ver > nul
            """
          }
        }
      }
    }

    stage('Deploy: Staging') {
      steps {
        // Docker Desktop must be installed and available in PATH
        bat "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          bat """
            echo %DOCKER_PASS% | docker login -u %DOCKER_USER% --password-stdin
            docker push ${IMAGE_NAME}:${IMAGE_TAG}
          """
        }
        // docker compose v2 (CLI) syntax:
        bat """
          set IMAGE_TAG=${IMAGE_TAG}
          docker compose -f docker-compose.staging.yml up -d --remove-orphans
          ping -n 3 127.0.0.1 > nul
          curl -fsS http://localhost:3000/health || ver > nul
        """
      }
    }

    stage('Release: Promote to Prod (Manual)') {
      steps {
        input message: "Promote build #${env.BUILD_NUMBER} (v${RELEASE_VERSION}) to PROD?", ok: 'Release'
        bat "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          bat """
            echo %DOCKER_PASS% | docker login -u %DOCKER_USER% --password-stdin
            docker push ${IMAGE_NAME}:latest
          """
        }
        // Git tagging on Windows
        bat 'git config user.email "ci@example.com" || ver > nul'
        bat 'git config user.name "ci" || ver > nul'
        bat "git tag -a v${RELEASE_VERSION} -m \"Release ${RELEASE_VERSION}\" || ver > nul"
        bat "git push --tags || ver > nul"

        // Deploy prod
        bat "docker compose -f docker-compose.prod.yml up -d --remove-orphans"
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
