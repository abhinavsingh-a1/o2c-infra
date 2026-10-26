.PHONY: jenkins-up jenkins-down prod-down

# Jenkins for the promotion pipelines (o2c-app ADR-018, docs/jenkins.md): built and started
# by Ansible in a runner container; http://localhost:18090
jenkins-up:
	scripts/ansible.sh jenkins.yml

# Removes the Jenkins container; the volume o2c-jenkins-home (jobs, builds, audit log) stays
jenkins-down:
	scripts/ansible.sh jenkins.yml -e jenkins_state=absent

# Frees the memory of o2c-prod. Argo CD shows the prod applications OutOfSync until the
# next sync (prod has no self-heal); promote-to-prod syncs them back to Git.
prod-down:
	kubectl --context kind-o2c -n o2c-prod scale deployment --all --replicas=0
