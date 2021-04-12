FROM ruby:3.0.0
ENV PATH /root/.yarn/bin:$PATH

RUN apt-get update -qq && apt-get install -y nodejs build-essential
RUN apt-get install -y libpq-dev postgresql-client
RUN apt-get install -y libxml2-dev libxslt1-dev
RUN curl -o- -L https://yarnpkg.com/install.sh | bash

WORKDIR /application
COPY Gemfile /application/Gemfile
COPY Gemfile.lock /application/Gemfile.lock
RUN bundle install

COPY package.json /application/package.json
COPY yarn.lock /application/yarn.lock
RUN yarn install

COPY . /application

RUN rails webpacker:install

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0"]
