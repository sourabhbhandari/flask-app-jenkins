// Jenkinsfile for the flask-app-jenkins demo app.
//
// Loads the shared library dynamically from GitHub so no Jenkins admin
// config is required. Once you register the library in Jenkins (Manage
// Jenkins → System → Global Pipeline Libraries) you can replace the
// `library(...)` call with the simpler annotation form:
//
//     @Library('jenkins-shared-lib@main') _
//
library identifier: 'jenkins-shared-lib@main',
        retriever: modernSCM([
            $class: 'GitSCMSource',
            remote: 'https://github.com/sourabhbhandari/jenkins-shared-library.git'
            // credentialsId: 'github-creds'   // only if the repo were private
        ])

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
        url:  'host.docker.internal:10091',
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
        repoUrl:        'https://github.com/sourabhbhandari/flask-app-jenkins.git',
        targetRevision: 'main',
        chartPath:      'charts/flask-app-jenkins',
        namespace:      'flask-app',
        argoNamespace:  'argocd'
    ]
)
