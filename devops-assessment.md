DevOps - Technical Assessment

1. Background
You are asked to prepare infrastructure and deployment configuration for a simplified repository for PayTrack, an internal payment-reconciliation API used by operations staff.
The service is intended to run on Amazon EKS. Terraform is used to manage AWS infrastructure, and GitHub Actions is used to validate changes through CI.
Keep the following context in mind:
●	The API is intended for internal use only.
●	The VPC and private subnets are assumed to already exist and are managed by the platform team.
●	No AWS credentials or live cloud resources will be provided or are required for this assessment.
●	The platform team is small, so proposed solutions should be practical to implement and maintain.
●	The application is intentionally simple. You are not expected to develop application features.
The repository has been simplified for this assessment. Some files may be incomplete or illustrative.
2. Your Task
You have approximately 2 days to complete the assessment. You may use AI tools, public documentation, and validation or security-scanning tools. You are responsible for reviewing and understanding the output of any tools you use.
A. Write Terraform Configuration for EKS
Create Terraform configuration in the infra/ directory to manage:
●	AWS provider configuration and an appropriate provider version.
●	An EKS cluster.
●	The IAM role and policy attachments required by the cluster.
●	A managed node group, including its IAM role and required policy attachments.
●	Use of the existing VPC and private subnets through input variables.
●	Relevant variables, outputs, and tags.
Requirements:
●	The AWS region must be configurable rather than hardcoded throughout the configuration.
●	Do not expose administrative access broadly without justification.
●	Do not include access keys, secret keys, or other sensitive values in Terraform files.
●	Provide an example input file, such as terraform.tfvars.example, without real credentials.
●	Document important assumptions about networking and cluster/node access.
●	Include validation steps that do not create cloud resources.
You may use a maintained module if you explain the version and why you chose it. Your submission must still make clear how the cluster, node group, IAM, and networking are configured. You do not need to create the VPC from scratch.
B. Write Kubernetes Manifests
Create manifests in k8s/ to run the API on EKS. Include at least:
●	A Namespace.
●	A Deployment.
●	A Service.
●	A ConfigMap for non-sensitive configuration, if needed.
You do not need to implement every possible Kubernetes control. Prioritize controls appropriate to the scenario and explain important decisions or assumptions.
C. Create a GitHub Actions Validation Workflow
Create a workflow under .github/workflows/ to validate changes. At a minimum, the workflow should:
●	Run on pull requests.
●	Check Terraform formatting and configuration.
●	Validate Kubernetes manifests.
●	Run at least one infrastructure-as-code security check.
●	Use the minimum permissions needed.
●	Keep validation separate from deployment.
●	Fail clearly when a required check fails.
You may use tools such as terraform fmt -check, terraform init -backend=false, terraform validate, a Kubernetes manifest validator, and an IaC scanner such as Checkov or Trivy. If a tool is not available in the CI environment, explain how it would be installed or use an appropriate action/container.
Deployment automation is optional. If you propose it, explain secure AWS authentication (for example, OIDC and short-lived credentials), environment protection, and required approvals. Do not use long-lived AWS access keys.
D. Investigate the Troubleshooting Scenario
Review the artifacts in troubleshooting/. The API is experiencing intermittent HTTP 5xx responses after a new release, even though some pods appear to be Running.
Write a short diagnosis covering:
1.	Your leading hypothesis and the evidence supporting it.
2.	The next checks or commands you would run.
3.	How you would distinguish an application issue from a readiness, resource, or networking issue.
4.	When you would roll back.
5.	The most valuable preventive improvements.
There is no single required answer. We are assessing evidence-based reasoning, not guessing.
E. Explain Your Approach
Explain your work in a format you are comfortable with. Cover:
1.	Your main design decisions and assumptions.
2.	How you would validate your work without creating cloud resources.
3.	The key security and operational trade-offs.
4.	What you did not finish and why.
5.	Your use of AI or other tools, including at least one suggestion you verified, changed, or rejected.
3. Constraints
●	Do not create cloud resources or run terraform apply.
●	Do not add real credentials, tokens, or secrets.
●	If a check cannot be run locally, explain how it would work and clearly state whether it has been implemented or is only a recommendation.
●	You do not need to build a complete production deployment.
●	Reasonable assumptions are allowed, but explain them.
●	Do not spend all your time trying to implement every possible control. Prioritization, safe defaults, and clear reasoning matter more than the number of files or controls.
4. Deliverables
Please provide:
●	The Terraform configuration in infra/.
●	The Kubernetes manifests in k8s/.
●	The GitHub Actions workflow in .github/workflows/.
●	The modified files, repository, a patch, or a pull request.
●	An explanation of your findings, fixes, decisions, and recommendations in any format you prefer.
You may include your explanation in the repository or provide it separately as a document or presentation. The format is up to you.
5. Live Technical Discussion
After the assessment, there will be a 45-minute technical discussion.
You are required to submit your assessment deliverables along with supporting slides at least one day before the technical discussion.
Prepare slides explaining the rationale behind your implementation and technical decisions, including design considerations, trade-offs, assumptions, and alternatives you considered. The interviewer will review your slides before the session.
The discussion will focus directly on Q&A based on your assessment submission and supporting slides.
The last 15 minutes will be reserved for you to ask the Kirimo team questions. Please prepare a list of questions in advance! :)
