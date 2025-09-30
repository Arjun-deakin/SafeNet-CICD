pipeline {
  agent any
  options { timestamps() }

  environment {
    RELEASE_VERSION     = "1.0.${env.BUILD_NUMBER}"
    IMAGE_NAME          = "arjundeakin/safenet-api"
    IMAGE_TAG           = "${env.BUILD_NUMBER}"
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
          bat 'node -v'
          bat 'npm -v'
          // retry helps with transient registry hiccups
          retry(2) { bat 'npm ci' }
          // prove deps exist
          bat 'if not exist node_modules (echo node_modules missing && exit /b 1)'
          bat 'dir /b node_modules | findstr /i "jest" || echo (jest folder not listed yet)'
          bat 'dir /b node_modules | findstr /i "supertest" || echo (supertest folder not listed yet)'
        }
      }
    }

    stage('Test') {
      steps {
        withEnv(["PATH=${env.NODEJS_HOME}\\bin;${env.PATH}"]) {
          // fix IF syntax: run npm ci only if node_modules is missing
          bat 'if not exist node_modules (npm ci)'
          bat 'npx jest --coverage'
        }
        archiveArtifacts artifacts: 'coverage/**', fingerprint: true
      }
    }

    stage('Code Quality (SonarCloud)') {
      steps {
        withSonarQubeEnv('SONARCLOUD') {
          bat "\"%SONAR_SCANNER_HOME%\\bin\\sonar-scanner.bat\" -Dsonar.projectVersion=${RELEASE_VERSION}"
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
                def ceJson = bat(script: "curl -s -u %SC_TOKEN%: ${serverUrl}/api/ce/task?id=${ceTaskId}", returnStdout: true).trim()
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
            def qgJson = bat(script: "curl -s -u %SC_TOKEN%: ${serverUrl}/api/qualitygates/project_status?analysisId=${env.SONAR_ANALYSIS_ID}", returnStdout: true).trim()
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
              npx snyk auth %SNYK_TOKEN% || ver > nul
              npx snyk test || ver > nul
              npx snyk monitor || ver > nul
            """
          }
        }
      }
    }

    // --- everything Docker below runs on a node labeled 'docker' ---
    stage('Preflight: Docker Daemon') {
      agent { label 'docker' }
      steps {
        // Fail here (with a clear message) if the daemon isn't reachable
        script {
          def ok = isUnix()
            ? (sh(script: 'docker info >/dev/null 2>&1', returnStatus: true) == 0)
            : (bat(script: 'docker info >nul 2>&1', returnStatus: true) == 0)
          if (!ok) {
            error "Docker daemon not reachable on this node. Fix Docker or move deploy to a working 'docker' node."
          }
        }
      }
    }

    stage('Deploy: Staging') {
      agent { label 'docker' }
      steps {
        bat "docker version" // works on Windows docker node; use sh on Linux nodes
        // If your docker node is Linux-only, replace 'bat' with 'sh' in this stage & below.
        bat "docker build --pull -t ${IMAGE_NAME}:${IMAGE_TAG} ."
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          bat """
            echo %DOCKER_PASS% | docker login -u %DOCKER_USER% --password-stdin
            docker push ${IMAGE_NAME}:${IMAGE_TAG}
          """
        }
        // compose: pass IMAGE_TAG as an env var so ${IMAGE_TAG:-staging} resolves
        bat """
          set IMAGE_TAG=${IMAGE_TAG}
          docker compose -f docker-compose.staging.yml up -d --remove-orphans
          ping -n 3 127.0.0.1 > nul
          curl -fsS http://localhost:3000/health || ver > nul
        """
      }
    }

    stage('Release: Promote to Prod (Manual)') {
      agent { label 'docker' }
      steps {
        input message: "Promote build #${env.BUILD_NUMBER} (v${RELEASE_VERSION}) to PROD?", ok: 'Release'
        bat "docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest"
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          bat """
            echo %DOCKER_PASS% | docker login -u %DOCKER_USER% --password-stdin
            docker push ${IMAGE_NAME}:latest
          """
        }
        bat 'git config user.email "ci@example.com" || ver > nul'
        bat 'git config user.name "ci" || ver > nul'
        bat "git tag -a v${RELEASE_VERSION} -m \"Release ${RELEASE_VERSION}\" || ver > nul"
        bat "git push --tags || ver > nul"
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
