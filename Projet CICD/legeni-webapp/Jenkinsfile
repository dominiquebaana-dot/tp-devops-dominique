// PROJET FINAL DEVOPS (Lots 4 & 5 + Bonus) : Chaîne CI/CD complète du commit à la production
pipeline {
    agent any

    parameters {
        string(name: 'DOCKERHUB_ID', defaultValue: 'heyitsdom', description: 'Identifiant Docker Hub (ou registre local)')
    }

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '15'))
    }

    stages {
        stage('Initialisation') {
            steps {
                script {
                    env.APP_BASE_VERSION = readFile('VERSION').trim()
                    def branchPart = (env.BRANCH_NAME ?: 'dev').replaceAll('[^a-zA-Z0-9.-]', '-')
                    env.APP_TAG = (env.BRANCH_NAME == 'main') ? "${env.APP_BASE_VERSION}-${env.BUILD_NUMBER}" : "${branchPart}-${env.BUILD_NUMBER}"
                    env.IMAGE = "${params.DOCKERHUB_ID}/legeni-webapp"
                    echo "Build ${env.IMAGE}:${env.APP_TAG} (branche : ${env.BRANCH_NAME ?: 'locale'})"
                }
            }
        }

        stage('Contrôles Qualité (Parallèle)') {
            parallel {
                stage('Tests & Couverture (>=80%)') {
                    agent {
                        docker {
                            image 'python:3.12-slim'
                            args '-e HOME=/tmp'
                            reuseNode true
                        }
                    }
                    steps {
                        sh '''
                            python -m venv /tmp/venv
                            /tmp/venv/bin/pip install -q -r requirements.txt -r requirements-dev.txt
                            mkdir -p reports
                            /tmp/venv/bin/pytest --junitxml=reports/junit.xml \
                                --cov=app --cov-report=xml:reports/coverage.xml --cov-fail-under=80
                        '''
                    }
                    post {
                        always {
                            junit 'reports/junit.xml'
                            recordCoverage(tools: [[parser: 'COBERTURA', pattern: 'reports/coverage.xml']])
                        }
                    }
                }

                stage('Lint Python (Flake8)') {
                    agent {
                        docker {
                            image 'python:3.12-slim'
                            args '-e HOME=/tmp'
                            reuseNode true
                        }
                    }
                    steps {
                        sh '''
                            python -m venv /tmp/venv
                            /tmp/venv/bin/pip install -q flake8==7.1.1
                            mkdir -p reports
                            /tmp/venv/bin/flake8 --output-file=reports/flake8.txt --tee app.py tests/
                        '''
                    }
                    post {
                        always {
                            recordIssues(tools: [flake8(pattern: 'reports/flake8.txt')])
                        }
                    }
                }

                stage('Lint Dockerfile (Hadolint)') {
                    steps {
                        sh 'docker run --rm -i hadolint/hadolint:v2.12.0 < Dockerfile'
                    }
                }

                stage('Syntaxe Ansible') {
                    steps {
                        dir('ansible') {
                            sh '''
                                ansible-playbook --syntax-check provision.yml
                                ansible-playbook --syntax-check deploy.yml -e vault_file=vars/vault.yml.example
                            '''
                        }
                    }
                }
            }
        }

        stage('Build Image Multi-Stage') {
            steps {
                sh '''
                    docker build --target test -t legeni-webapp:test .
                    docker build --build-arg APP_VERSION="$APP_TAG" -t "$IMAGE:$APP_TAG" .
                '''
            }
        }

        stage('Scan Sécurité (Trivy)') {
            steps {
                sh '''
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
                        aquasec/trivy:0.57.1 image --severity CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE:$APP_TAG"
                '''
            }
        }

        stage('Push Registre (main uniquement)') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'registry-credentials',
                                                  usernameVariable: 'REG_USER',
                                                  passwordVariable: 'REG_TOKEN')]) {
                    sh '''
                        echo "$REG_TOKEN" | docker login -u "$REG_USER" --password-stdin
                        docker push "$IMAGE:$APP_TAG"
                        docker logout
                    '''
                }
            }
        }

        stage('Déploiement Staging (Ansible -> K8s)') {
            when { branch 'main' }
            steps {
                withCredentials([
                    file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG'),
                    file(credentialsId: 'ansible-vault-pass', variable: 'VAULT_PASS_FILE')
                ]) {
                    dir('ansible') {
                        sh '''
                            ansible-playbook deploy.yml \
                                --vault-password-file "$VAULT_PASS_FILE" \
                                -e target_env=staging \
                                -e webapp_image="$IMAGE" \
                                -e app_version="$APP_TAG"
                        '''
                    }
                }
            }
        }

        stage('Validation Humaine Production') {
            when { branch 'main' }
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    input message: "Promouvoir la version ${APP_TAG} en PRODUCTION (legeni-prod) ?", ok: 'Déployer en Production'
                }
            }
        }

        stage('Déploiement Production (Ansible -> K8s + Rollback Auto)') {
            when { branch 'main' }
            steps {
                withCredentials([
                    file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG'),
                    file(credentialsId: 'ansible-vault-pass', variable: 'VAULT_PASS_FILE')
                ]) {
                    dir('ansible') {
                        sh '''
                            ansible-playbook deploy.yml \
                                --vault-password-file "$VAULT_PASS_FILE" \
                                -e target_env=prod \
                                -e webapp_image="$IMAGE" \
                                -e app_version="$APP_TAG"
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline réussi : ${env.IMAGE}:${env.APP_TAG}"
        }
        failure {
            echo "❌ Échec du pipeline ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.BUILD_URL})"
            script {
                try {
                    withCredentials([string(credentialsId: 'webhook-notification', variable: 'WEBHOOK_URL')]) {
                        sh '''
                            curl -s -H "Content-Type: application/json" \
                                -d "{\\"content\\": \\"❌ Échec du pipeline **${JOB_NAME}** #${BUILD_NUMBER} (version ${APP_TAG:-inconnue}) : ${BUILD_URL}console\\"}" \
                                "$WEBHOOK_URL" || true
                        '''
                    }
                } catch (ignored) {
                    echo "Notification externe ignorée (credential 'webhook-notification' non défini)."
                }
            }
        }
        cleanup {
            cleanWs()
        }
    }
}
