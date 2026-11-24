.PHONY: check shellcheck dry-run

SHELL := /usr/bin/env bash

check: shellcheck dry-run

shellcheck:
	shellcheck bin/k8s-cost-review test/mock/kubectl test/assert-report.sh

dry-run:
	bash test/assert-report.sh
