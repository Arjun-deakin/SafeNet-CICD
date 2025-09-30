pipeline {
  agent any
  options { timestamps(); ansiColor('xterm') }

  /***************
   * ENVIRONMENT *
   ***************/
  environment {
    // ---- Versioning (used by SonarCloud "Previous version" and Git tags) ----
    RELEASE_VERSION = "1.0.${env.BUILD_NUMBER}"

    // ---- Docker image coordinates (adjust username/repo) ----
    IMAGE_NAME = "your-dockerhub-username/safenet-api"
    IMAGE_TAG  = "${env.BUILD_NUMBER}"

    // ---- Jenkins tool names (set in Manage Jenkins → Global Tool Configuration) ----
    NODEJS_HOME         = tool 'node20'         // NodeJS 20 (name must match your Jenkins tools)
    SONAR_SCANNER_HOME  = tool 'sonar-scanner'  // SonarQube Scanner (name must match)

    // ---- Sonar "server" name (Manage Jenkins → System → SonarQube servers) ----
    // We call SonarCloud via withSonarQubeEnv('SONARCLOUD') for auth/URL envs
  }

  stages {

    /************
     * Checkout *
     ************/
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git rev-parse --short HEAD || true'
      }
    }

    /********
     * Build *
     ********/
    stage('Build') {
      tools { nodejs 'node20' } // ensures Node on PATH
      steps {
        sh """
          node -v
          npm -v
          npm ci
        """
      }
    }

    /*******
     * Test *
     *******/
    stage('Test') {
      steps {
        sh 'npm test -- --coverage'
        // If you add jest-junit, enable the next line and point to the correct path:
        // junit 'reports/junit.xml'
        archiveArtifacts artifacts: 'coverage/**', fingerprint: true
      }
    }

    /*************************
     * Code Quality (Scan)   *
     *************************/
    stage('Code Quality (SonarCloud)') {
      steps {
        withSonarQubeEnv('SONARCLOUD') {
          // SonarCloud scan (CI-based analysis). DO NOT use Auto Analysis in SonarCloud project.
          sh """
            ${SONAR_SCANNER_HOME}/bin/sonar-scanner \
              -Dsonar.projectVersion=${RELEASE_VERSION}
          """
        }
      }
    }

    /*****************************************************************
     * Quality Gate (SonarCloud, no webhooks — poll the API instead) *
     *****************************************************************/
    stage('Quality Gate (SonarCloud – no webhook)') {
      steps {
        script {
          // Sonar scanner writes task info to .scannerwork/report-task.txt
          def props = readProperties file: '.scannerwork/report-task.txt'
          def ceTaskId = props['ceTaskId']
          def serverUrl = props['serverUrl'] ?: 'https://sonarcloud.io'

          withCredentials([string(credentialsId: 'SONARCLOUD_TOKEN', variable: 'SC_TOKEN')]) {
            // 1) Wait for background task to complete (up to 5 minutes)
            timeout(time: 5, unit: 'MINUTES') {
              waitUntil {
                def ceJson = sh(
                  script: "curl -s -u ${SC_TOKEN}: ${serverUrl}/api/ce/task?id=${ceTaskId}",
                  returnStdout: true
                ).trim()
                // crude regex parse to avoid jq dependency
                def mStatus = (ceJson =~ /\"status\":\"([A-Z_]+)\"/)
                if (!mStatus.find()) {
                  echo "Unable to parse CE status, will retry..."
                  sleep 3; return false
                }
                def status = mStatus.group(1)
                echo "SonarCloud CE task status: ${status}"

                if (status == 'SUCCESS') {
                  def mAnalysis = (ceJson =~ /\"analysisId\":\"([^\"]+)\"/)
                  if (mAnalysis.find()) {
                    env.SONAR_ANALYSIS_ID = mAnalysis.group(1)
                    return true
                  } else {
                    error "CE task success but no analysisId found"
                  }
                } else if (status in ['PENDING','IN_PROGRESS']) {
                  sleep 3; return false
                } else {
                  error "SonarCloud CE task failed: ${status}"
                }
              }
            }

            // 2) Fetch Quality Gate result for this analysis
            def qgJson = sh(
              script: "curl -s -u ${SC_TOKEN}: ${serverUrl}/api/qualitygates/project_status?analysisId=${env.SONAR_ANALYSIS_ID}",
              returnStdout: true
            ).trim()

            def mQG = (qgJson =~ /\"status\":\"([A-Z]+)\"/)
            if (!mQG.find()) {
              error "Unable to read Quality Gate status from SonarCloud response"
            }
            def qg = mQG.group(1)
            echo "SonarCloud Quality Gate: ${qg}"
            if (qg != 'OK') {
              error "Quality Gate failed: ${qg}"
            }
          }
        }
      }
    }

    /***********************
     * Security (Snyk CLI) *
     ***********************/
    stage('Security (Snyk)') {
      steps {
        withEnv(["PATH=${env.NODEJS_HOME}/bin:${env.PATH}"]) {
          withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
            sh """
              npm ci
              npx snyk auth ${SNYK_TOKEN} || true
              npx snyk test || true       # fail build later if you want strict gate
              npx snyk monitor || true    # send snapshot to SonarCloud/Snyk dashboard
            """
          }
        }
      }
    }

    /****************************************
     * Build & Push Docker, Deploy Staging  *
     ****************************************/
    stage('Deploy: Staging') {
      steps {
        sh """
          docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
        """
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          sh """
            echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
            docker push ${IMAGE_NAME}:${IMAGE_TAG}
          """
        }
        sh """
          IMAGE_TAG=${IMAGE_TAG} docker compose -f docker-compose.staging.yml up -d --remove-orphans
          sleep 3
          curl -fsS http://localhost:3000/health || true
        """
      }
    }

    /************************************************
     * Manual Release: Tag + Promote Image to Prod  *
     ************************************************/
    stage('Release: Promote to Prod (Manual)') {
      steps {
        input message: "Promote build #${env.BUILD_NUMBER} (v${RELEASE_VERSION}) to PROD?", ok: 'Release'
        sh """
          docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
        """
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          sh """
            echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
            docker push ${IMAGE_NAME}:latest
          """
        }
        // Tag repo with same version used in Sonar (keeps "Previous version" in sync with releases)
        sh 'git config user.email "ci@example.com" || true'
        sh 'git config user.name "ci" || true'
        sh 'git tag -a v${RELEASE_VERSION} -m "Release ${RELEASE_VERSION}" || true'
        sh 'git push --tags || true'

        // Deploy prod stack (expects a host with compose & port 80 mapped)
        sh 'IMAGE_TAG=latest docker compose -f docker-compose.prod.yml up -d --remove-orphans'
      }
    }

    /*****************************
     * Monitoring (PrometheusIO) *
     *****************************/
    stage('Monitoring & Alerting') {
      steps {
        echo 'Prometheus scraping /metrics. Grafana dashboard recommended.'
        echo 'Example alert: rate(safenet_requests_total[5m]) == 0 for 10m → "No traffic".'
      }
    }
  }

  /********
   * Post *
   ********/
  post {
    always {
      archiveArtifacts artifacts: 'docker-compose.*.yml, sonar-project.properties', onlyIfSuccessful: false
    }
    success {
      echo "Pipeline succeeded. Image: ${IMAGE_NAME}:${IMAGE_TAG}, Version: ${RELEASE_VERSION}"
    }
    failure {
      echo "Pipeline failed. Check logs for Sonar/Snyk/Build stages."
    }
  }
}
