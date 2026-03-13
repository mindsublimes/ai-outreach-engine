#!/usr/bin/env bash
set -o errexit

bundle install
bundle exec rails assets:precompile
bundle exec rails assets:clean
# Prepare all databases (primary + queue); idempotent for Render
bundle exec rails db:prepare
