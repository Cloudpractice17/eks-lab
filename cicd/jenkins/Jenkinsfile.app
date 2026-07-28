// FULL CI/CD PIPELINE — Java App
// ─────────────────────────────────────────────────────────────────────
// WHAT HAPPENS ON EVERY PUSH:
//   1.  Checkout source code
//   2.  Maven: compile + unit tests
//   3.  SonarQube: code quality scan (fails build if Quality Gate fails)
//   4.  Maven: package (builds the .jar)
//   5.  Docker: build image tagged with Git commit SHA
//   6.  Trivy: scan image for CVEs (fails on HIGH/CRITICAL)
//   7.  ECR: push image (only if all scans pass)
//   8.  Nexus: publish Maven artifact
//
// WHAT HAPPENS ON MERGE TO main (ADDITIONAL STEPS):
//   9.  GitOps repo: update dev/manifests with new image tag
//  10.  Argo CD: auto-syncs dev (no manual step needed)
//  11.  GATE: wait for dev deployment to be healthy (5 min timeout)
//  12.  APPROVAL: human reviews dev, approves prod promotion
//  13.  GitOps repo: update prod/manifests with same image tag
//  14.  Argo CD: manual sync prod (human triggers in Argo CD UI)
//
// WHY the image tag is the Git SHA, not "latest":
// "latest" is mutable — it means different things at different times.
// The SHA is immutable and traceable. Every running pod in prod can be
// traced back to an exact commit.

pipeline {
  agent any

  environment {
    // ── App config ─────────────────────────────────────────────────
    APP_NAME     = "myapp"
    MAVEN_OPTS   = "-Dmaven.repo.local=.m2"

    // ── AWS / ECR ───────────────────────────────────────────────────
    AWS_REGION        = "us-east-1"
    AWS_ACCOUNT_ID    = credentials("aws-account-id")
    ECR_REGISTRY      = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    ECR_REPO          = "${ECR_REGISTRY}/eks-lab/${APP_NAME}"
    IMAGE_TAG         = "${GIT_COMMIT[0..7]}"  // first 8 chars of commit SHA
    FULL_IMAGE        = "${ECR_REPO}:${IMAGE_TAG}"

    // ── GitOps repo ─────────────────────────────────────────────────
    GITOPS_REPO       = "https://github.com/YOUR_ORG/gitops-repo.git"
    GITOPS_REPO_SSH   = "git@github.com:YOUR_ORG/gitops-repo.git"

    // ── Tool URLs (internal DNS — from Route 53 module) ─────────────
    SONAR_URL         = "http://sonarqube.eks.internal:9000"
    NEXUS_URL         = "http://nexus.eks.internal:8081"
    ARGOCD_URL        = "http://argocd.eks.internal"
  }

  options {
    ansiColor("xterm")
    timeout(time: 60, unit: "MINUTES")
    buildDiscarder(logRotator(numToKeepStr: "20"))
    // WHY disableConcurrentBuilds: two builds writing to the same
    // GitOps repo simultaneously will cause merge conflicts.
    disableConcurrentBuilds()
  }

  stages {

    // ── 1. Checkout ────────────────────────────────────────────────
    stage("Checkout") {
      steps {
        checkout scm
        script {
          env.GIT_AUTHOR   = sh(script: "git log -1 --pretty=%an", returnStdout: true).trim()
          env.GIT_MESSAGE  = sh(script: "git log -1 --pretty=%s",  returnStdout: true).trim()
        }
        echo "Building commit ${IMAGE_TAG} by ${GIT_AUTHOR}: ${GIT_MESSAGE}"
      }
    }

    // ── 2. Maven: compile + unit tests ────────────────────────────
    stage("Build & Test") {
      steps {
        sh """
          mvn clean test \
            -Dmaven.repo.local=.m2 \
            --batch-mode \
            --fail-at-end
        """
      }
      post {
        always {
          // Publish JUnit results so Jenkins shows pass/fail per test
          junit "**/target/surefire-reports/*.xml"
        }
      }
    }

    // ── 3. SonarQube: code quality gate ───────────────────────────
    stage("SonarQube Scan") {
      steps {
        // WHY withSonarQubeEnv: this injects the SonarQube token from
        // Jenkins credentials store (which reads from SSM) into the
        // Maven command automatically. The token never appears in logs.
        withSonarQubeEnv("sonarqube") {
          sh """
            mvn sonar:sonar \
              -Dsonar.projectKey=${APP_NAME} \
              -Dsonar.host.url=${SONAR_URL} \
              -Dmaven.repo.local=.m2 \
              --batch-mode
          """
        }
      }
    }

    stage("Quality Gate") {
      steps {
        // WHY a separate stage: waitForQualityGate polls SonarQube
        // until the analysis completes (can take 1-2 min). Putting it
        // in its own stage makes it visible in the pipeline view.
        timeout(time: 5, unit: "MINUTES") {
          waitForQualityGate abortPipeline: true
          // abortPipeline: true means a failing quality gate fails the
          // build. This is the gate — code with new bugs or coverage
          // regressions cannot proceed to Docker build.
        }
      }
    }

    // ── 4. Maven: package ─────────────────────────────────────────
    stage("Package") {
      steps {
        sh """
          mvn package -DskipTests \
            -Dmaven.repo.local=.m2 \
            --batch-mode
        """
        archiveArtifacts artifacts: "target/*.jar", fingerprint: true
      }
    }

    // ── 5. Docker: build image ────────────────────────────────────
    stage("Docker Build") {
      steps {
        sh """
          docker build \
            --build-arg JAR_FILE=target/${APP_NAME}-*.jar \
            --label git-commit=${IMAGE_TAG} \
            --label build-date=\$(date -u +%Y-%m-%dT%H:%M:%SZ) \
            -t ${FULL_IMAGE} \
            -t ${ECR_REPO}:latest \
            .
        """
      }
    }

    // ── 6. Trivy: container vulnerability scan ───────────────────
    stage("Trivy Scan") {
      steps {
        sh """
          # WHY --exit-code 1 on HIGH/CRITICAL:
          # This makes Trivy fail the build if it finds HIGH or CRITICAL
          # CVEs. The image never reaches ECR — and therefore never
          # reaches your cluster — if it has serious vulnerabilities.
          trivy image \
            --exit-code 1 \
            --severity HIGH,CRITICAL \
            --no-progress \
            --format table \
            ${FULL_IMAGE}
        """
      }
      post {
        always {
          // Save the full Trivy report for audit — even if the build
          // passes, having a record of what was scanned is good practice
          sh """
            trivy image \
              --format json \
              --output trivy-report-${IMAGE_TAG}.json \
              ${FULL_IMAGE} || true
          """
          archiveArtifacts artifacts: "trivy-report-*.json", allowEmptyArchive: true
        }
      }
    }

    // ── 7. ECR: push image ────────────────────────────────────────
    stage("Push to ECR") {
      steps {
        sh """
          # Authenticate Docker to ECR using the Jenkins instance's
          # IAM role — no username/password stored anywhere
          aws ecr get-login-password --region ${AWS_REGION} | \
            docker login --username AWS --password-stdin ${ECR_REGISTRY}

          docker push ${FULL_IMAGE}
          docker push ${ECR_REPO}:latest

          echo "Pushed: ${FULL_IMAGE}"
        """
      }
    }

    // ── 8. Nexus: publish Maven artifact ─────────────────────────
    stage("Publish to Nexus") {
      steps {
        withCredentials([
          // WHY withCredentials here and not an env var:
          // Jenkins fetches this from SSM at build time. It's injected
          // into the environment only for the duration of this block
          // and masked in all log output.
          usernamePassword(
            credentialsId: "nexus-credentials",
            usernameVariable: "NEXUS_USER",
            passwordVariable: "NEXUS_PASS"
          )
        ]) {
          sh """
            mvn deploy \
              -DskipTests \
              -DaltDeploymentRepository=nexus::default::${NEXUS_URL}/repository/maven-releases/ \
              -Dmaven.repo.local=.m2 \
              --batch-mode
          """
        }
      }
    }

    // ── 9–10. GitOps: update dev manifests ───────────────────────
    stage("Deploy to Dev") {
      when { branch "main" }
      steps {
        withCredentials([
          string(credentialsId: "github-token", variable: "GH_TOKEN")
        ]) {
          sh """
            # Clone the GitOps repo (separate from the app source repo)
            git clone https://x-token-auth:${GH_TOKEN}@github.com/YOUR_ORG/gitops-repo.git gitops-repo
            cd gitops-repo

            # Update the image tag in dev manifests
            # sed replaces the image tag in the Kubernetes Deployment YAML
            sed -i 's|image: ${ECR_REPO}:.*|image: ${FULL_IMAGE}|g' \
              dev/manifests/deployment.yaml

            git config user.email "jenkins@eks-lab.internal"
            git config user.name "Jenkins CI"
            git add dev/manifests/deployment.yaml
            git commit -m "ci: deploy ${APP_NAME}:${IMAGE_TAG} to dev [skip ci]"
            # WHY [skip ci]: prevents this commit from triggering
            # another pipeline run in a loop.
            git push origin main

            echo "GitOps repo updated — Argo CD will sync dev automatically"
          """
        }
      }
    }

    // ── 11. Wait for dev to be healthy ───────────────────────────
    stage("Verify Dev Deployment") {
      when { branch "main" }
      steps {
        sh """
          # Wait up to 5 minutes for the dev rollout to complete
          kubectl rollout status deployment/${APP_NAME} \
            -n myapp-dev \
            --timeout=5m

          echo "Dev deployment is healthy. Ready for prod promotion."
        """
      }
    }

    // ── 12. Prod promotion gate ───────────────────────────────────
    stage("Approve Prod Promotion") {
      when { branch "main" }
      steps {
        timeout(time: 24, unit: "HOURS") {
          input(
            message: """
              Dev is healthy with image ${IMAGE_TAG}.
              Commit: ${GIT_MESSAGE}
              Author: ${GIT_AUTHOR}

              Promote this image to PROD?
            """,
            ok: "Promote to Prod",
            submitter: "senior-engineer,tech-lead"
          )
        }
      }
    }

    // ── 13. GitOps: update prod manifests ────────────────────────
    stage("Update Prod GitOps") {
      when { branch "main" }
      steps {
        withCredentials([
          string(credentialsId: "github-token", variable: "GH_TOKEN")
        ]) {
          sh """
            cd gitops-repo

            sed -i 's|image: ${ECR_REPO}:.*|image: ${FULL_IMAGE}|g' \
              prod/manifests/deployment.yaml

            git add prod/manifests/deployment.yaml
            git commit -m "ci: promote ${APP_NAME}:${IMAGE_TAG} to prod [skip ci]"
            git push origin main

            echo "Prod manifests updated. Trigger sync in Argo CD UI."
            echo "Argo CD URL: ${ARGOCD_URL}"
            echo "App: myapp-prod"
            echo "Image: ${FULL_IMAGE}"
          """
        }
      }
    }

    // ── 14. Argo CD: trigger prod sync ───────────────────────────
    stage("Sync Prod via Argo CD") {
      when { branch "main" }
      steps {
        withCredentials([
          string(credentialsId: "argocd-token", variable: "ARGOCD_TOKEN")
        ]) {
          sh """
            # WHY argocd CLI here and not kubectl:
            # The argocd CLI handles authentication, waits for sync
            # completion, and reports health status in one command.
            # kubectl apply would skip Argo CD entirely and break GitOps.

            argocd app sync myapp-prod \
              --server ${ARGOCD_URL} \
              --auth-token ${ARGOCD_TOKEN} \
              --grpc-web \
              --prune

            argocd app wait myapp-prod \
              --server ${ARGOCD_URL} \
              --auth-token ${ARGOCD_TOKEN} \
              --grpc-web \
              --health \
              --timeout 300

            echo "Prod deployment complete and healthy."
          """
        }
      }
    }
  }

  post {
    success {
      echo "Pipeline complete. ${APP_NAME}:${IMAGE_TAG} is live in prod."
    }
    failure {
      echo "Pipeline failed at stage: ${currentBuild.result}"
      // Add Slack notification here — ask me to wire that in next
    }
    always {
      // Clean workspace to avoid disk fill from Docker layers
      sh "docker rmi ${FULL_IMAGE} ${ECR_REPO}:latest || true"
      cleanWs()
    }
  }
}
