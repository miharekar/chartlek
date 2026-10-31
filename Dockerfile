# syntax=docker/dockerfile:1
# check=error=true

# bin/up passes the version from .ruby-version.
ARG RUBY_VERSION
FROM docker.io/rubylang/ruby:${RUBY_VERSION:?}-resolute AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libyaml-0-2 sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

RUN bundle exec bootsnap precompile app/ lib/

RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server"]
