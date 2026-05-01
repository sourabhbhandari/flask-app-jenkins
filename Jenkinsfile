// Jenkinsfile for the flask-app-jenkins demo app.
//
// Uses the jenkins-shared-lib registered in Jenkins as "jenkins-shared-lib".
// Pin to a tag for stability when you have one (e.g. @v1.0.0).
@Library('jenkins-shared-lib@main') _

ciCdPipeline(
    app: [
        name:       'flask-app-jenkins',
        dockerfile: 'Dockerfile',
        context:    '.',
        chartDir:   'charts/flask-app-jenkins'
    ],
    registry: [
        // Local registry running at localhost:5000 (set up below in the README).
        // Leave url empty and push:false to keep the image in the local docker daemon
        // (works for docker-desktop k8s with imagePullPolicy: IfNotPresent).
        url:  'localhost:5000',
        push: true
        // credentialsId: 'docker-registry-creds'   // only for private registries
    ],
    sbom: [
        format: 'cyclonedx'
    ],
    minio: [
        endpoint:      'http://localhost:9001',
        bucket:        'sboms',
        credentialsId: 'minio-creds'        // create in Jenkins (see README)
    ],
    argocd: [
        // The Helm chart and ArgoCD config typically live in a separate "config" repo.
        // For this demo we point ArgoCD at this same repo so it picks up charts/flask-app-jenkins.
        // Replace with your own URL when you fork/push.
        repoUrl:        'https://github.com/sourabh/flask-app-jenkins.git',
        targetRevision: 'main',
        chartPath:      'charts/flask-app-jenkins',
        namespace:      'flask-app',
        argoNamespace:  'argocd'
    ]
)
