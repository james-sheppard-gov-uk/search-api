ARG base_image=ruby:2.7.5-slim-buster

FROM $base_image AS builder

ENV RAILS_ENV=production

# TODO: have a separate build image which already contains the build-only deps.
RUN apt-get update -qq && \
    apt-get upgrade -y && \
    apt-get install -y build-essential nodejs && \
    apt-get clean

RUN mkdir /app

WORKDIR /app
COPY Gemfile* .ruby-version /app/

RUN bundle config set deployment 'true' && \
    bundle config set without 'development test' && \
    bundle install -j8 --retry=2

COPY . /app

FROM $base_image

ENV RAILS_ENV=production GOVUK_APP_NAME=search-api LOG_TO_STDOUT=true

RUN apt-get update -qy && \
    apt-get upgrade -y && \
    apt-get install -y nodejs && \
    apt-get clean

COPY --from=builder /usr/local/bundle/ /usr/local/bundle/
COPY --from=builder /app /app/

WORKDIR /app

CMD bundle exec puma
