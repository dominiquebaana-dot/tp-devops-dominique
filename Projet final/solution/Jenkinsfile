// Pipeline CI/CD IC GROUP (Legeni Academy + Rôles Ansible Odoo & pgAdmin)
pipeline {
    agent any

    environment {
        DOCKERHUB_ID = "heyitsdom"
        IMAGE_NAME   = "${DOCKERHUB_ID}/legeni-academy"
    }

    stages {
        stage('Lecture de releases.txt') {
            steps {
                script {
                    env.APP_VERSION = sh(script: "awk 'NR==3 {print \$2}' releases.txt", returnStdout: true).trim()
                    env.ODOO_URL    = sh(script: "awk 'NR==1 {print \$2}' releases.txt", returnStdout: true).trim()
                    env.PGADMIN_URL = sh(script: "awk 'NR==2 {print \$2}' releases.txt", returnStdout: true).trim()
                    echo "Version=${env.APP_VERSION}, ODOO_URL=${env.ODOO_URL}, PGADMIN_URL=${env.PGADMIN_URL}"
                }
            }
        }

        stage('Build Image Legeni Academy') {
            steps {
                sh 'docker build -t ${IMAGE_NAME}:${APP_VERSION} .'
            }
        }

        stage('Test Container Legeni Academy') {
            steps {
                sh '''
                    docker rm -f test-legeni-academy 2>/dev/null || true
                    if [ -f /.dockerenv ] && docker inspect jenkins >/dev/null 2>&1; then
                        JNET=$(docker inspect jenkins -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
                        docker run -d --name test-legeni-academy --network "${JNET}" ${IMAGE_NAME}:${APP_VERSION}
                        TARGET="http://test-legeni-academy:8080"
                    else
                        docker run -d --name test-legeni-academy -p 18080:8080 ${IMAGE_NAME}:${APP_VERSION}
                        TARGET="http://localhost:18080"
                    fi
                    for i in $(seq 1 15); do curl -sf "${TARGET}" >/dev/null && break; sleep 1; done
                    curl -sf "${TARGET}" | grep -q "Legeni Academy"
                    curl -sf "${TARGET}" | grep -q "${ODOO_URL}"
                    curl -sf "${TARGET}" | grep -q "${PGADMIN_URL}"
                '''
            }
            post {
                always {
                    sh 'docker rm -f test-legeni-academy 2>/dev/null || true'
                }
            }
        }

        stage('Push Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
                    sh '''
                        echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${APP_VERSION}
                    '''
                }
            }
        }

        stage('Déploiement Production (Ansible + Kubernetes)') {
            steps {
                dir('ansible') {
                    sh 'ansible-playbook --syntax-check deploy_icgroup.yml'
                }
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        kubectl set image deployment/legeni-academy-deployment \
                            legeni-academy=${IMAGE_NAME}:${APP_VERSION} -n icgroup
                        kubectl rollout status deployment/legeni-academy-deployment -n icgroup --timeout=120s
                    '''
                }
            }
        }
    }
}
