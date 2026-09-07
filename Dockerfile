FROM ruby:4.0.6-slim-trixie

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git libpq-dev libyaml-dev \
      libvips poppler-utils && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /aim-helm-rails
COPY Gemfile aim-helm-rails.gemspec ./
RUN bundle install
COPY . .

ENV RAILS_ENV=test
CMD ["bundle", "exec", "rspec"]
