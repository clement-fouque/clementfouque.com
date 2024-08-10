# Define variables
HUGO_CMD := hugo
SITE_DIR := blog

# Default target
.PHONY: all
all: build

# Build the site
.PHONY: build
build:
	@echo "Building the site..."
	$(HUGO_CMD) --source $(SITE_DIR)

# Serve the site locally
.PHONY: serve
serve:
	@echo "Serving the site locally..."
	$(HUGO_CMD) server --source $(SITE_DIR)

# Serve the site locally
.PHONY: dev
dev:
	@echo "Serving the site locally with draft content..."
	$(HUGO_CMD) server --source $(SITE_DIR) --buildDrafts

# Clean the build artifacts
# .PHONY: clean
# clean:
# 	@echo "Cleaning the build artifacts..."
# 	rm -rf $(SITE_DIR)

# New post
.PHONY: new
new:
	@echo "Creating a new post..."
	$(HUGO_CMD) new $(SITE_DIR)/posts/$(NEW_POST_TITLE).md

# Help message
.PHONY: help
help:
	@echo "Usage:"
	@echo "  make                Build the site"
	@echo "  make serve          Serve the site locally"
	# @echo "  make clean          Clean the build artifacts"
	@echo "  make new            Create a new post"
	@echo "  make help           Show this help message"
