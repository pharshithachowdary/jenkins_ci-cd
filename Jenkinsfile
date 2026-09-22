// Jenkinsfile
// CI/CD pipeline: checkout -> install -> test -> build image -> push to ECR
// -> deploy to AWS EC2 -> validate health -> notify.
//
// Required Jenkins credentials (Manage Jenkins > Credentials):
//   aws-credentials        - AWS access key/secret (or use an instance profile)
//   ec2-ssh-key            - SSH private key credential for the deploy target
//   github-token           - (if using a private repo / webhook status updates)
//
// Required Jenkins plugins: Pipeline, Docker Pipeline, SSH Agent, JUnit, Git.

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    parameters {
        string(name: 'DEPLOY_ENV', defaultValue: 'staging', description: 'Target environment: staging | production')
    }

    environment {
        APP_NAME        = 'cicd-automation-platform'
        IMAGE_TAG       = "${env.BUILD_NUMBER}-${GIT_COMMIT?.take(7) ?: 'local'}"
        AWS_REGION      = 'us-east-1'
        ECR_REPO        = "123456789012.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}"
        EC2_HOST        = credentials('ec2-deploy-host')   // e.g. ec2-user@X.X.X.X, stored as a secret text credential
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                }
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh '''
                    python3 -m venv .venv
                    . .venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements-dev.txt
                '''
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    . .venv/bin/activate
                    flake8 app tests --max-line-length=100 --statistics
                    black --check app tests
                '''
            }
        }

        stage('Test') {
            steps {
                sh '''
                    . .venv/bin/activate
                    pytest tests/ \
                        --junitxml=reports/junit.xml \
                        --cov=app --cov-report=xml --cov-report=term
                '''
            }
            post {
                always {
                    junit 'reports/junit.xml'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    dockerImage = docker.build("${ECR_REPO}:${IMAGE_TAG}")
                }
            }
        }

        stage('Push to ECR') {
            when { branch 'main' }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REPO}
                    """
                    script {
                        dockerImage.push("${IMAGE_TAG}")
                        dockerImage.push("latest")
                    }
                }
            }
        }

        stage('Deploy to AWS EC2') {
            when { branch 'main' }
            steps {
                sshagent(credentials: ['ec2-ssh-key']) {
                    sh """
                        ssh -o StrictHostKeyChecking=no ${EC2_HOST} '
                            bash -s' < scripts/deploy.sh ${ECR_REPO} ${IMAGE_TAG}
                    """
                }
            }
        }

        stage('Post-Deploy Health Validation') {
            when { branch 'main' }
            steps {
                script {
                    // EC2_HOST is of the form "user@host"; extract the bare host for the URL.
                    def hostAddress = env.EC2_HOST.split('@').last()
                    sh "scripts/health_check.sh http://${hostAddress}:8000/health 10 5"
                }
            }
        }
    }

    post {
        success {
            echo "Build #${env.BUILD_NUMBER} succeeded: ${APP_NAME}:${IMAGE_TAG} deployed to ${params.DEPLOY_ENV}."
        }
        failure {
            echo "Build #${env.BUILD_NUMBER} FAILED at stage: ${env.STAGE_NAME}. Triggering rollback check."
            // Roll back to the previous known-good image if deploy/health-check failed.
            script {
                if (env.STAGE_NAME in ['Deploy to AWS EC2', 'Post-Deploy Health Validation']) {
                    sshagent(credentials: ['ec2-ssh-key']) {
                        sh """
                            ssh -o StrictHostKeyChecking=no ${EC2_HOST} '
                                bash -s' < scripts/rollback.sh ${ECR_REPO}
                        """
                    }
                }
            }
            // Wire up your notifier of choice, e.g.:
            // slackSend(channel: '#deployments', color: 'danger',
            //           message: "FAILED: ${APP_NAME} build #${env.BUILD_NUMBER} (${env.STAGE_NAME})")
        }
        always {
            sh 'docker image prune -f || true'
            cleanWs()
        }
    }
}
