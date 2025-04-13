SHELL := /usr/bin/bash
SRC_DIR := ${CURDIR}/src

SYSTEMD_SERVICE_FILES := bupstash-notify-fail@.service bupstash-notify-success@.service bupstash-backup@.service check-metered-connection.service
SYSTEMD_TIMER_FILES := bupstash-backup@.timer

USER_SYSTEMD_DIRECTORY := ${HOME}/.config/systemd/user
USER_LOCALBIN_DIRECTORY := ${HOME}/.local/bin
USER_LOCALCONFIG_DIRECTORY := ${HOME}/.config/bupstash
USER_LOCALLOG_DIRECTORY := ${HOME}/.local/bupstash

BUPSTASH_DEFAULT_REPOSITORY := ssh://bupstash.domain.tld/backups/storage/username/
BUPSTASH_DEFAULT_KEY := ${HOME}/path/to/bupstash.key

NTFY_DEFAULT_SERVER := https://ntfy.sh
NTFY_DEFAULT_TOPIC := test

EXCLUSION_LIST_FILE := ${PWD}/exclusion_list

EXECUTABLES = bash bupstash busctl egrep install ls mkdir rm sed systemctl

LOGGING_FUNCTION = @echo "--- ${1}"
.DEFAULT_GOAL := help
.PHONY: help install uninstall

check:
	$(call LOGGING_FUNCTION, Check prerequisites)
	$(foreach exec, ${EXECUTABLES}, $(if $(shell command -v $(exec) 2>/dev/null), \
		, $(error [!] $(exec) util not found in $$PATH)))
	@echo "[=] All prerequisites have been met"
	@echo

install: enable_systemctl reload_systemctl_daemon ## Install systemd files, reload user systemd files and enable them
uninstall: uninstall_systemd_files reload_systemctl_daemon ## Uninstall systemd files, reload user systemd files, preserve the configuration and logs
clean: clean_systemd_service_file ## Clean rendered systemd files from templates

create_directories: check
	$(call LOGGING_FUNCTION,Create bupstash directories if necessary)
	@for dir in ${USER_LOCALCONFIG_DIRECTORY} ${USER_LOCALLOG_DIRECTORY}; do \
		if [[ ! -d "$$dir" ]]; then \
			echo "[+] $$dir"; \
			mkdir $$dir; \
		fi; \
	done
	@echo

create_configuration: create_directories
	$(call LOGGING_FUNCTION,Create demo configuration)
	@if [[ ! -f "${USER_LOCALCONFIG_DIRECTORY}/config" ]]; then \
		echo "[+] ${USER_LOCALCONFIG_DIRECTORY}/config"; \
		touch "${USER_LOCALCONFIG_DIRECTORY}/config"; \
		echo -ne "BUPSTASH_REPOSITORY=${BUPSTASH_DEFAULT_REPOSITORY}\nBUPSTASH_KEY=${BUPSTASH_DEFAULT_KEY}\nNTFY_TOKEN=\nNTFY_SERVER=${NTFY_DEFAULT_SERVER}\nNTFY_TOPIC=${NTFY_DEFAULT_TOPIC}\n" > "${USER_LOCALCONFIG_DIRECTORY}/config"; \
	fi;
	@echo

render_systemd_templates: create_configuration
	$(call LOGGING_FUNCTION,Render systemd files)
ifneq ("$(wildcard ${EXCLUSION_LIST_FILE})","")
	@for template_file in $$(ls ${SRC_DIR}/*.template); do \
		if [[ "$$template_file" =~ "bupstash-backup@.template" ]]; then \
			echo "[^] Render exclusion rules"; \
			while read pattern; do [[ ! -z $$pattern ]] && exclusions+=" --exclude \"$$pattern\""; done < ${EXCLUSION_LIST_FILE}; \
		fi; \
		install -m 0644 -v "$$template_file" "${SRC_DIR}/$$(basename -s .template $$template_file).service"; \
		sed -i "s|%%EXCLUSIONS%%|$$exclusions|" "${SRC_DIR}/$$(basename -s .template $$template_file).service"; \
	done
	@echo
else
	@for template_file in $$(ls "${SRC_DIR}/*.template"); do \
		install -m 0644 -v "$$template_file" "${SRC_DIR}/$$(basename -s .template $$template_file).service"; \
		sed -i "s|%%EXCLUSIONS%%||" "${SRC_DIR}/$$(basename -s .template $template_file).service"; \
	done
	@echo
endif

install_systemd_files: render_systemd_templates
	$(call LOGGING_FUNCTION,Install systemd user files)
	@for file in ${SYSTEMD_SERVICE_FILES} ${SYSTEMD_TIMER_FILES}; do \
		echo "[+] $$(basename $$file)"; \
		install -m 0644 -D -v ${SRC_DIR}/$$file -t ${USER_SYSTEMD_DIRECTORY}; \
	done
	@echo

enable_systemctl: install_systemd_files
	$(call LOGGING_FUNCTION,Enable systemd user services)
	@for file in ${SYSTEMD_SERVICE_FILES}; do \
		if ! [[ "$$file" =~ '@' ]]; then \
			echo "[*] $$(basename $$file)"; \
			systemctl --user enable $$(basename $$file); \
		fi; \
	done
	@echo

disable_systemctl: check
	$(call LOGGING_FUNCTION,Disable systemd user services)
	@-for file_name in ${SYSTEMD_SERVICE_FILES}; do \
		if ! [[ "$$file_name" =~ '@' ]] ; then \
			echo "[-] $$(basename $$file_name)"; \
			systemctl --user disable --now $$(basename $$file_name) 2>/dev/null; \
		fi; \
	done
	@echo

reload_systemctl_daemon:
	$(call LOGGING_FUNCTION,Reload systemd user daemon)
	@systemctl --user daemon-reload
	@echo

uninstall_systemd_files: disable_systemctl
	$(call LOGGING_FUNCTION,Uninstall systemd user files)
	@for file in ${SHELL_FILES} ${SYSTEMD_SERVICE_FILES} ${SYSTEMD_TIMER_FILES}; do \
		if [[ -f "${USER_SYSTEMD_DIRECTORY}/$$(basename $$file)" ]]; then \
			echo "[-] ${USER_SYSTEMD_DIRECTORY}/$$(basename $$file)"; \
			rm "${USER_SYSTEMD_DIRECTORY}/$$(basename $$file)"; \
		fi; \
	done
	@echo

clean_systemd_service_file:
	$(call LOGGING_FUNCTION,Clean systemd service file)
	@-for file_name in $$(ls ${SRC_DIR}/*); do \
		if [[ "$$file_name" =~ '@.service' ]] && \
		   [[ -f "$$file_name" ]] ; then \
			echo "[-] $$(basename $$file_name)"; \
			rm -f "$$file_name"; \
		fi; \
	done
	@echo

readme: ## How to configure Systemd timers
	$(call LOGGING_FUNCTION,Readme)
	@echo 'Please follow to https://github.com/freefd/articles/9_backup_environment_using_bupstash/'
	@-xdg-open https://github.com/freefd/articles/9_backup_environment_using_bupstash/ 2>/dev/null

help: ## Show all usable commands
	@sed -e '/^[a-zA-Z0-9_\-]*:.*\#\#/!d' -e 's/:.*\#\#\s*/:/' \
		-e 's/^\(.\+\):\(.*\)/\1:\2/' $(MAKEFILE_LIST) | awk -F: '{print $$1"\n\t - "$$2}'
	@echo
