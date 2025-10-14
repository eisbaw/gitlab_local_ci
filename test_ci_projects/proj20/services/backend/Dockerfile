FROM ruby:3.2-alpine

RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    nodejs \
    tzdata

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

COPY . .

RUN bundle exec rake assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
