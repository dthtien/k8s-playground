
 
--
<h1>Deploying a Rails application to Kubernetes</h1>
    
   <p>©2021 <a href="https://collimarco.com">Marco Colli</a>, Founder / CTO @ <a href="https://pushpad.xyz">Pushpad - Web Push Notifications</a></p>
    
   <p>There are many ways to deploy a Ruby on Rails application: one of them is using Docker containers and Kubernetes for orchestration. This guide shows some of the advantages of Kubernetes compared to other solutions and explains how to deploy a Rails application in production using Kubernetes. We focus on the usage of containers for production, rather than development, and we value simple solutions. This guide covers all the common aspects required for running a Rails application in production, including the deployment and continuous delivery of the web application, the configuration of a load balancer and domain, the environment variables and secrets, the compilation of assets, the database migrations, logging and monitoring, the background workers and cron jobs, and how to run maintenance tasks and updates.</p>
    
   <nav id="nav">
   <ol>
   <li><a href="#alternatives">History and alternatives to Kubernetes</a></li>
   <li><a href="#prerequisites">Prerequisites</a></li>
   <li><a href="#git">The Git repository</a></li>
   <li><a href="#docker">The Docker image</a></li>
   <li><a href="#kubernetes">The Kubernetes cluster</a></li>
   <li><a href="#domain">Domain name and SSL</a></li>
   <li><a href="#env">Environment variables</a></li>
   <li><a href="#secrets">Secrets</a></li>
   <li><a href="#logging">Logging</a></li>
   <li><a href="#workers">Background jobs</a></li>
   <li><a href="#cron">Cron jobs</a></li>
   <li><a href="#console">Console</a></li>
   <li><a href="#rake">Rake tasks</a></li>
   <li><a href="#migrations">Database migrations</a></li>
   <li><a href="#deploy">Continuous delivery</a></li>
   <li><a href="#monitoring">Monitoring</a></li>
   <li><a href="#security">Security updates</a></li>
   <li><a href="#conclusion">Conclusion</a></li>
   </ol>
   </nav>
    
   <h2 id="alternatives">History and alternatives to Kubernetes</h2>
   <p>The easiest way for deploying a Rails application is probably using a PaaS, like Heroku, which makes the deployment and scaling extremely simple and lets you forget about servers. However:</p>
   <ul>
   <li>as the application scales, the cost may become prohibitive for your kind of business;</li>
   <li>you don't have full control of your application, which is managed by others, and this may raise concerns about uptime;</li>
   <li>you have constraints imposed by the platform;</li>
   <li>your application may become bounded to a specific platform, raising portability concerns.</li>
   </ul>
   <p>A cheaper alternative is using a IaaS, like DigitalOcean. You can start with a single server, but soon you will need to scale horizontally on multiple servers. Usually you have at least one load balancer with HAProxy, some web servers with nginx and Puma, a database (probably Postgresql and Redis with replicas) and maybe some separate servers for background processing (e.g. Sidekiq). When you need to scale the application you just create a snapshot of a server and you replicate it. You can also manage or update multiple servers with pssh or using configuration management tools like Chef and the application can be easily deployed with Capistrano. It is not very hard to create and configure a bunch of servers. However:</p>
   <ul>
   <li>the initial setup requires some time and knowledge;</li>
   <li>applying changes to many servers may become painful;</li>
   <li>running the wrong command on a fleet of servers may be difficult to revert;</li>
   <li>you must make sure to keep all the servers updated with the same configuration;</li>
   <li>scaling requires a lot of manual work.</li>
   </ul>
   <p>Kubernetes offers the advantages of a PaaS at the cost of a IaaS, so it is a good compromise that you should consider. It is also an open source technology and most cloud providers already offer it as a managed service.</p>
   <p>Let's see how to deploy a Rails application in production using Kubernetes.</p>
    
   <h2 id="prerequisites">Prerequisites</h2>
   <p>This guide assumes that you already have general knowledge about web development.</p>
   <p>We also expect that you already have a development machine with all the necessary applciations installed, including Ruby (e.g. using rbenv), Ruby on Rails, Git, Docker, etc.</p>
   <p>You also need to have an account on Docker Hub and DigitalOcean in order to try Kubernetes (or you can use your favorite alternatives).</p>
    
   <h2>The Rails application</h2>
   <p>You can use an existing Rails application or you can create an example Rails application with this command:</p>
   <pre><code>
   rails new kubernetes-rails-example
   </code></pre>
   <p>Then add a simple page to the example application:</p>
   <i>config/routes.rb</i>
   <pre><code>
   Rails.application.routes.draw do
   root 'pages#home'
   end
   </code></pre>
   <i>app/controllers/pages_controller.rb</i>
   <pre><code>
   class PagesController &lt; ApplicationController
   def home
   end
   end
   </code></pre>
   <i>app/views/pages/home.html.erb</i>
   <pre><code>
   &lt;h1&gt;Hello, world!&lt;/h1&gt;
   </code></pre>
    
   <h2 id="git">The Git repository</h2>
   <p>Let's save the changes in the local Git repository, which was already initialized by Rails:</p>
   <pre><code>
   git add .
   git commit -m "Initial commit"
   </code></pre>
   <p>Then we need to create a Git repository online. Go to Github and create a new repository, then connect the local repository to the remote one and publish the changes:</p>
   <pre><code>
   git remote add origin https://github.com/<var>username</var>/kubernetes-rails-example.git
   git push -u origin master
   </code></pre>
   <p>Although a Git repository is not strictly required for Docker and Kubernetes, I mention it here because most CI/CD tools, including Docker Hub, can be connected to your Git repository in order to build the Docker image automatically whenever you push some changes.</p>
    
   <h2 id="docker">The Docker image</h2>
   <p>First step for containerization is to create the Docker image. A Docker image is simply a package which contains our application, together with all the dependencies and system libraries needed to run it.</p>
   <p>Add this file in the root folder of your Rails application:</p>
   <i>Dockerfile</i>
   <pre><code>
   FROM ruby:2.5
    
   RUN apt-get update &amp;&amp; apt-get install -y nodejs yarn postgresql-client
    
   RUN mkdir /app
   WORKDIR /app
   COPY Gemfile Gemfile.lock ./
   RUN gem install bundler
   RUN bundle install
   COPY . .
    
   RUN rake assets:precompile
    
   EXPOSE 3000
   CMD ["rails", "server", "-b", "0.0.0.0"]
   </code></pre>
   <p>First we use <code>FROM</code> to tell Docker to download a public image, which is then used as the base for our custom image. In particular we use an image which contains a specific version of Ruby.</p>
   <p>Then we use <code>RUN</code> to execute a command inside the image that we are building. In particular we use <code>apt-get</code> to install some libraries. Note that the libraries available on the default Ubuntu repositories are usually quite old: if you want to get the latest versions you need to update the repository list and tell APT to download the libraries directly from the maintainer's repository. In particular, just before <code>apt-get</code>, we can add the following commands to update the Node.js and Yarn repositories:</p>
   <pre><code>
   RUN curl https://deb.nodesource.com/setup_12.x \ bash
   RUN curl https://dl.yarnpkg.com/debian/pubkey.gpg \ apt-key add -
   RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" \ tee /etc/apt/sources.list.d/yarn.list
   </code></pre>
   <p>In the next block of code, we copy our Rails application to the image and we install all the required gems using Bundler. The Gemfile is copied before the other application code because Docker can use caching to build the image faster in case there aren't any changes to the Gemfile.</p>
   <p>We also run a task to precompile the assets (stylesheets, scripts, etc.).</p>
   <p>Finally we configure a default command to be executed on the image.</p>
   <p>Before building the image we want to make sure that some files are not copied to it: this is important to exclude <i>secrets</i>, for security, and useless directories, like <code>tmp</code> or <code>.git</code>, which would be a waste of resources. For this we need to create a <code>.dockerignore</code> file in the Rails root: you can usually take inspiration from your <code>.gitignore</code>, since the aim and syntax are very similar.</p>
   <p>It's time to build the image:</p>
   <pre><code>
   docker build -t <var>username</var>/kubernetes-rails-example:latest .
   </code></pre>
   <p>The <code>-t</code> option, followed by its argument, is optional: we use it to assign a <i>name</i> and a <i>tag</i> to the new image. This makes it easier to find the image later. We can also use a <i>repository</i> name as the image name, in order to allow push to that repository later. The image name is the part before the colon, while the tag is the part after the colon. Note that we could also omit the tag <code>latest</code> since it is the default value used in case the tag is omitted. The last dot is a required argument and indicates the path to the Dockerfile.</p>
   <p>Then you can see that the image is actually available on your machine:</p>
   <pre><code>
   docker image ls
   </code></pre>
   <p>You can also use the image ID or its name to run the image (a running image is called a <i>container</i>):</p>
   <pre><code>
   docker run -p 3000:3000 <var>username</var>/kubernetes-rails-example:latest
   </code></pre>
   <p>Note that we map the host port 3000 (on the left) to the container port 3000 (on the right). You can also use other ports if you prefer: however, if you change the container port, you also need to update the image to make sure that the Rails server listens on the correct port and you also need to open that port using <code>EXPOSE</code>.</p>
   <p>You can now see your webiste by visiting <code>http://localhost:3000</code>.</p>
   <p>Finally we can push the image to the online repository. First you need to sign up to Docker Hub, or to another <i>registry</i> and create a <i>reposotory</i> there for your image. Then you can push the local image to the remote repository:</p>
   <pre><code>
   docker push <var>username</var>/kubernetes-rails-example:latest
   </code></pre>
    
   <h2 id="kubernetes">The Kubernetes cluster</h2>
   <p>It's time to create the Kubernetes cluster for production. Go to your favorite Kubernetes provider and create a cluster using the dashboard: we will use DigitalOcean for this tutorial.</p>
   <p>Once the cluster is created you need to downlooad the credential and cluster configuration to your machine, so that you can connect to the cluster. For example you can move the configuration file to <code>~/.kube/kubernetes-rails-example-kubeconfig.yaml</code>. Then you need to pass a <code>--kubeconfig</code> option to <code>kubektl</code> whenever you invoke a command, or you can set an environment variable:</p>
   <pre><code>
   export KUBECONFIG=~/.kube/kubernetes-rails-example-kubeconfig.yaml
   </code></pre>
   <p>Then you need to make sure that you have Kubernetes installed and that it can connect to the remote cluster. Run this command:</p>
   <pre><code>
   kubectl version
   </code></pre>
   <p>You should see the version of your command line tools and the version of the cluster.</p>
   <p>You can also play around with this command:</p>
   <pre><code>
   kubectl get nodes
   </code></pre>
   <p>A <i>node</i> is simply a server managed by Kubernetes. Then Kubernetes creates some virtual machines (in a broad sense) called <i>pods</i> on each node, based on our configuration. Pods are distributed automatically by Kubernetes on the available nodes and, in case a node fails, Kubernetes will move the pod to a different node. A pod usually contains a single <i>container</i>, but it can also have multiple related containers that need to share some resources.</p>
   <p>The next step is to run some pods with our Docker image. Since our Docker image is probably hosted in a private repository, we need to give the Docker credentials to Kubernetes, so that it can download the image. Run these commands:</p>
   <pre><code>
   kubectl create secret docker-registry <var>my-docker-secret</var> --docker-server=<var>DOCKER_REGISTRY_SERVER</var> --docker-username=<var>DOCKER_USER</var> --docker-password=<var>DOCKER_PASSWORD</var> --docker-email=<var>DOCKER_EMAIL</var>
   kubectl edit serviceaccounts default
   </code></pre>
   <p>And add this to the end after <code>Secrets</code>:</p>
   <pre><code>
   imagePullSecrets:
   - name: <var>my-docker-secret</var>
   </code></pre>
   <p>Then you can define the Kubernetes configuration: create a <code>config/kube</code> directory in your Rails application.</p>
   <p>We start by defining a deploy for the Rails application:</p>
   <i>config/kube/deployment.yml</i>
   <pre><code>
   apiVersion: apps/v1
   kind: Deployment
   metadata:
   name: kubernetes-rails-example-deployment
   spec:
   replicas: 4
   selector:
   matchLabels:
   app: rails-app
   template:
   metadata:
   labels:
   app: rails-app
   spec:
   containers:
   - name: rails-app
   image: <var>username</var>/kubernetes-rails-example:latest
   ports:
   - containerPort: 3000
   </code></pre>
   <p>The above is a minimal deployment:</p>
   <ul>
   <li><code>apiVersion</code> sets the API version for the configuration file;</li>
   <li><code>kind</code> sets the type of configuration file;</li>
   <li><code>metadata</code> is used to assign a name to the deployment;</li>
   <li><code>replicas</code> tells Kubernetes to spin up a given number of pods;</li>
   <li><code>selector</code> tells Kubernetes what template to use to generate the pods;</li>
   <li><code>template</code> defines the template for a pod;</li>
   <li><code>spec</code> sets the Docker image that we want to run inside the pods and other configurations, like the container port that must be exposed.</li>
   </ul>
   <p>Now we also need to forward and distribute the HTTP requests to the pods. Let's create a load balancer:</p>
   <i>config/kube/load_balancer.yml</i>
   <pre><code>
   apiVersion: v1
   kind: Service
   metadata:
   name: kubernetes-rails-example-load-balancer
   spec:
   type: LoadBalancer
   selector:
   app: rails-app
   ports:
   - protocol: TCP
   port: 80
   targetPort: 3000
   name: http
   </code></pre>
   <p>Basically we tell the load balancer:</p>
   <ul>
   <li>listen on the default port 80;</li>
   <li>forward the requests on port 3000 of the pods that have the label <code>rails-app</code>.</li>
   </ul>
   <p>Now we can apply the configuration to Kubernetes, using a <i>declarative</i> management:</p>
   <pre><code>
   kubectl apply -f config/kube
   </code></pre>
   <p>It't time to verify that the pods are running properly:</p>
   <ol>
   <li><code>kubectl get pods</code> shows the pods and their status;</li>
   <li>the status for all pods should be <code>Running</code>;</li>
   <li>if you see the error <code>ImagePullBackOff</code> probably you have not configured properly the secret to download the image from your private repository;</li>
   <li>you can get more details about any errors by running <code>kubectl describe pod <var>pod-name</var></code>;</li>
   <li>you can fix the configurations and then regenerate the pods by running <code>kubectl delete --all pods</code>.</li>
   </ol>
   <p>Now you can get the load balancer IP and other information by running the folowing commands:</p>
   <pre><code>
   kubectl get services
   kubectl describe service <var>service-name</var>
   </code></pre>
   <p>In particular you must find the <code>LoadBalancer Ingress</code> or <code>EXTERNAL-IP</code> and type it in your browser address bar: our website is up and running!</p>
    
   <h2 id="domain">Domain name and SSL</h2>
   <p>Probably your users won't access your website using the IP address, so you need to configure a domain name. Add the following record to your DNS:</p>
   <pre><code>
   <var>example.com.</var>   A   <var>192.0.2.0</var>
   </code></pre>
   <p>Obviously you need to replace the domain name with your domain and the IP address with the <i>external IP</i> of the load balancer (you can get it using <code>kubectl get services</code>).</p>
   <p>An SSL certificate can be added to your website using proprietary YAML configurations, but the easiest way, if you are using DigitalOcean, is to use their dashboard to configure the SSL certificate (i.e. go to the load balancer settings).</p>
    
   <h2 id="env">Environment variables</h2>
   <p>There are different solutions for storing environment variables:</p>
   <ul>
   <li>you can define the env variables inside your Rails configuration;</li>
   <li>you can define the env variables inside your Dockerfile;</li>
   <li>you can define the env variables using Kubernetes.</li>
   </ul>
   <p>I suggest that you use Kubernetes for managing the environment variables for production: that makes it easy to change them without having to build a new image each time. Also Kubernetes has more information available about your environment and it can set some variables dinamically for you (e.g. it can set a variable with the pod name or IP). Finally it offers more granularity when you have multiple deployments (e.g. Puma and Sidekiq), since you can set different values for each deployment.</p>
   <p>Add the following attribute to your <i>container</i> definition (e.g. after the <code>image</code> attribute) inside <i>config/kube/deployment.yml</i>:</p>
   <pre><code>
   env:
   - name: EXAMPLE
   value: This env variable is defined by Kubernetes.
   </code></pre>
   <p>Then you can update the Kubernetes cluster by running this command:</p>
   <pre><code>
   kubectl apply -f config/kube
   </code></pre>
   <p>If you want to make sure that everything works, you can try to print the env variable inside your app.</p>
   <p>For development and test you can use a gem called <i>dotenv</i> to easily define the env variables.</p>
   <p>For production you can also use Kubernetes <i>ConfigMaps</i> to define the env variables. The advantage of using this method is that you can define the env variables once and then use them for different <i>Deployments</i> or <i>Pods</i>. For example a Rails application usually requires the followig variables:</p>
   <i>config/kube/env.yml</i>
   <pre><code>
   apiVersion: v1
   kind: ConfigMap
   metadata:
   name: env
   data:
   RAILS_ENV: production
   RAILS_LOG_TO_STDOUT: enabled
   RAILS_SERVE_STATIC_FILES: enabled
   DATABASE_URL: postgresql://example.com/mydb
   REDIS_URL: redis://redis.default.svc.cluster.local:6379/
   </code></pre>
   <p>Then add the following attribute inside a <i>container</i> definition (e.g. after the <code>image</code> attribute):</p>
   <i>config/kube/deployment.yml</i>
   <pre><code>
   envFrom:
   - configMapRef:
   name: env
   </code></pre>
   <p>Remember that it is not safe to store secrets, like <code>SECRET_KEY_BASE</code>, in your Git repository! In the next section we will see how to use Rails credentials to safely store your secrets.</p>
    
   <h2 id="secrets">Secrets</h2>
   <p>You can store your secrets either in your Rails configuration or using Kubernetes secrets. I suggest that you use the Rails <i>credentials</i> to store your secrets: we will use Kubernetes secrets only to store the master key. Basically we store all our credentials in the Git repository, along with our application, but this is safe because we encrypt them with a master key. Then we use the master key, not stored in the Git repository, to access those secrets.</p>
   <p>Enable this option inside <i>config/environments/production.rb</i>:</p>
   <pre><code>
   config.require_master_key = true
   </code></pre>
   <p>Then run this command to edit your credentials:</p>
   <pre><code>
   EDITOR="vi" rails credentials:edit
   </code></pre>
   <p>While editing the file add the following line and then save and close:</p>
   <pre><code>
   example_secret: foobar
   </code></pre>
   <p>Then inside your app you can try to print the secret:</p>
   <i>app/views/pages/home.html.erb</i>
   <pre><code>
   &lt;%= Rails.application.credentials.example_secret %&gt;
   </code></pre>
   <p>Note that starting from Rails 6 you can also define different credentials for different environments.</p>
   <p>If you run your website locally you can see the secret displayed properly. The last thing that we need to do is to give the master key to Kubernetes in a secure way:</p>
   <pre><code>
   kubectl create secret generic rails-secrets --from-literal=rails_master_key='<var>example</var>'
   </code></pre>
   <p>Your master key is usually stored in <i>config/master.key</i>.</p>
   <p>Finally we need to pass the Kubernetes secret as an environment variable to our containers. Add this variable to your <code>env</code> inside <i>config/kube/deployment.yml</i>:</p>
   <pre><code>
   - name: RAILS_MASTER_KEY
   valueFrom:
   secretKeyRef:
   name: rails-secrets
   key: rails_master_key
   </code></pre>
   <p>In order to test if everything works, you can rebuild the Docker image and deploy the new configuration: you should see the example secret (not a real secret) displayed on your homepage.</p>
    
   <h2 id="logging">Logging</h2>
   <p>There are two different strategies for logging:</p>
   <ul>
   <li>send the logs directly from your Rails app to a centralized logging service;</li>
   <li>log to <i>stdout</i> and let Docker and Kubernetes collect the logs on the node.</li>
   </ul>
   <p>The first option is simple, but you don't collect the Kubernetes logs and might be less efficient. In any case you can use a gem like <i>logstash-logger</i> for this.</p>
   <p>If you want to use the second option, you can enable logging to stdout for your Rails app by settings the env variable <code>RAILS_LOG_TO_STDOUT</code> to <code>enabled</code>.</p>
   <p>Then you can see the latest logs using this command:</p>
   <pre><code>
   kubectl logs -l app=rails-app
   </code></pre>
   <p>Basically, when you run the command, the Kubernetes master node gets the latest logs from the nodes (only for pods with label <code>rails-app</code>) and displays them. This is useful for getting started, however logs are not persistent and you need to make them searchable. For this reason you need to send them to a centralized logging service: we can use Logz.io for example, which offers a managed ELK stack. In order to send the logs from Kubernetes to ELK we use Fluentd, which is a log collector written in Ruby and a CNCF graduated project.</p>
   <p>This is how logging works:</p>
   <ol>
   <li>your Rails application and other Kubernetes components write the logs to stdout;</li>
   <li>Kubernetes collects and store the logs on the nodes;</li>
   <li>you use a Kubernetes DaemonSet to run a Fluentd pod on each node;</li>
   <li>Fluentd reads the logs from the node and sends them to the centralized logging service;</li>
   <li>you can use the logging service to read, visualize and search all the logs.</li>
   </ol>
   <p>You can install Fluentd on your cluster with these simple commands:</p>
   <pre><code>
   kubectl create secret generic logzio-logs-secret --from-literal=logzio-log-shipping-token='MY_LOGZIO_TOKEN' --from-literal=logzio-log-listener='MY_LOGZIO_URL' -n kube-system
    
   kubectl apply -f https://raw.githubusercontent.com/logzio/logzio-k8s/master/logzio-daemonset-rbac.yaml
   </code></pre>
   <p>If you need custom configurations, you can download the file and edit it before running <code>kubectl apply</code>. Note that if you use services different from Logz.io the strategy is very similar and you can find many configuration examples on the Github repository <i>fluent/fluentd-kubernetes-daemonset</i>.</p>
   <p>You can verify if everything works by visiting your website and then checking the logs.</p>
    
   <h2 id="workers">Background jobs</h2>
   <p>Let's see how to run Sidekiq on Kubernetes, in order to have some background workers.</p>
   <p>First of all you need to add Sidekiq to your Rails application:</p>
   <i>Gemfile</i>
   <pre><code>
   gem 'sidekiq'
   </code></pre>
   <p>Then run <code>bundle install</code> and create an example worker:</p>
   <i>app/jobs/hard_worker.rb</i>
   <pre><code>
   class HardWorker
   include Sidekiq::Worker
    
   def perform(*args)
   # Do something
   Rails.logger.info 'It works!'
   end
   end
   </code></pre>
   <p>Finally add the following line to your <code>PagesController#home</code> method (or anywhere else) to create a background job every time a request is made:</p>
   <pre><code>
   HardWorker.perform_async
   </code></pre>
   <p>Now the interesting part: we need to add a new deployment to Kubernetes for running Sidekiq. The deployment is very similar to what we have already done for the web application: however, instead of running Puma as the main process of the container, we want to run Sidekiq. Here's the configuration:</p>
   <i>config/kube/sidekiq.yml</i>
   <pre><code>
   apiVersion: apps/v1
   kind: Deployment
   metadata:
   name: sidekiq
   spec:
   replicas: 2
   selector:
   matchLabels:
   app: sidekiq
   template:
   metadata:
   labels:
   app: sidekiq
   spec:
   containers:
   - name: sidekiq
   image: <var>username</var>/kubernetes-rails-example:latest
   command: ["sidekiq"]
   env:
   - name: REDIS_URL
   value: <var>redis://redis.default.svc.cluster.local:6379/</var>
   </code></pre>
   <p>Basically we define a new deployment with two pods: each pod runs our standard image that contains the Rails application. The most interesting part is that we set a <code>command</code> which overrides the default command defined in the Docker image. You can also pass some arguments to Sidekiq using an <code>args</code> key.</p>
   <p>Also note that we define a <code>REDIS_URL</code> variable, so that Sidekiq and Rails can connect to Redis to get and process the jobs. You should also add the same env variable to your web deployment, so that your Rails application can connect to Redis and schedule the jobs. For Redis itself you can use Kubernetes <i>StatefulSets</i>, you can install it on a custom server or use a managed solution: although it is easy to manage a single instance of Redis, scaling a Redis cluster is not straightforward and if you need scalability and reliability probably you should consider a managed solution.</p>
   <p>As always, you can apply the new configuration to Kubernetes with <code>kubectl apply -f config/kube</code>.</p>
   <p>Finally you can try to visit your website and make sure that everything works: when you load your homepage, the example job is scheduled and you should see <i>It works!</i> in your logs.</p>
    
   <h2 id="cron">Cron jobs</h2>
   <p>There are different strategies to create a cron job when you deploy to Kubernetes:</p>
   <ul>
   <li>use Kubernetes built-in cron jobs to run a container periodically;</li>
   <li>use some Ruby background processes to schedule and perform the jobs.</li>
   </ul>
   <p>A problem with the first approach is that you have to define a Kubernetes config file for each cron job. If you want to use this solution you can use <i>Kubernetes CronJobs</i> in combination with <i>rake tasks</i> or <i>rails runner</i>.</p>
   <p>If you use the second method, you can schedule the cron jobs easily using Ruby. Basically you need a Ruby process that is always running in background and takes care to create the jobs when the current time matches a cron pattern. For example you can install the <i>rufus-scheduler</i> gem and then run a dedicated container: however in this case you have a single point of failure and if the pod is rescheduled a job may be lost. In order to have a more distributed and relaible environment, we can use a gem like <i>sidekiq-cron</i>: it runs a scheduler thread on each sidekiq server process and it uses Redis in order to make sure that the same job is not scheduled multiple times. For example, if you have N sidekiq replicas, then there are N processes that check the schedule every minute and if the current time matches a cron line, then they try to get a Redis lock: if a thread manages to get the lock, it means that it is responsible for scheduling the Sidekiq jobs for that time, otherwise it simply does nothing. Finally the Sidekiq jobs are executed normally, as the other background jobs, and thus can easily scale horizontally on the existing pods and get a reliable processing with retries.</p>
   <p>Let's add this gem to the Rails application:</p>
   <i>Gemfile</i>
   <pre><code>
   gem 'sidekiq-cron'
   </code></pre>
   <p>Then run <code>bundle install</code> and create an initializer:</p>
   <i>config/initializers/sidekiq.rb</i>
   <pre><code>
   Sidekiq::Cron::Job.load_from_hash YAML.load_file('config/schedule.yml') if Sidekiq.server?
   </code></pre>
   <p>Finally define a schedule:</p>
   <i>config/schedule.yml</i>
   <pre><code>
   my_first_job:
   cron: "* * * * *"
   class: "HardWorker"
   </code></pre>
   <p>Then when you start Sidekiq you will see that the worker is executed once every minute, regardless of the number of pods running.</p>
    
   <h2 id="console">Console</h2>
   <p>You can connect to a pod by running this command:</p>
   <pre><code>
   kubectl exec -it <var>my-pod-name</var> bash
   </code></pre>
   <p>Basically we start the bash process inside the container and we attach our interactive input to it using the <code>-it</code> options.</p>
   <p>If you need a list of the pod names you can use <code>kubectl get pods</code>.</p>
   <p>Altough you can connect to any pod, I find it useful to create a single pod named <code>terminal</code> for maintenance tasks. Create the following file and then run <code>kubectl apply -f kube/config</code>:</p>
   <pre><code>
   apiVersion: v1
   kind: Pod
   metadata:
   name: terminal
   spec:
   containers:
   - name: terminal
   image: <var>username</var>/kubernetes-rails-example:latest
   command: ['sleep']
   args: ['infinity']
   env:
   - name: EXAMPLE
   value: This env variable is defined by Kubernetes.
   </code></pre>
   <p>All containers must have a main running process, otherwise they exit and Kubernetes considers that as a crash. Running the default command for the image, the Rails server, would be a waste of resources, since the pod is not connected to the load balancer: instead we use <code>sleep infinity</code>, which is basically a no-op that consumes less resources and keeps the container running.</p>
   <p>Once you are connected to the bash console of a pod you can easily run any command. If you want to run only a single command, you can also start it directly. For example, if you want to start the <i>Rails console</i> inside a pod named <code>terminal</code>, you can run this command:</p>
   <pre><code>
   kubectl exec -it <var>terminal</var> rails console
   </code></pre>
   <p>If you need to pass additional arguments to the process you can use <code>--</code> to separate the Kubernetes arguments from the command arguments. For example:</p>
   <pre><code>
   kubectl exec -it <var>terminal</var> -- rails console -e production
   </code></pre>
    
   <h2 id="rake">Rake tasks</h2>
   <p>There are different ways to run a rake task on Kubernetes:</p>
   <ul>
   <li>you can create a Kubernetes Job to run the rake task in a dedicated container;</li>
   <li>you can connect to an existing pod and run the rake task.</li>
   </ul>
   <p>For simplicity I prefer the second alternative.</p>
   <p>Run the following command to list all the pods available:</p>
   <pre><code>
   kubectl get pods
   </code></pre>
   <p>Then you can run a task with this command:</p>
   <pre><code>
   kubectl exec <var>my-pod-name</var> rake <var>task-name</var>
   </code></pre>
   <p>Note that <code>kubectl exec</code> returns the status code of the command executed (i.e. <code>0</code> if the rake task is executed successfully).</p>
    
   <h2 id="migrations">Database migrations</h2>
   <p>Migrating the database without downtime when you deploy a new version of your application is not a simple task. The origin of most problems is that both deploying the new code to all pods and running the database migration are long tasks that take some time to be completed. Basically they are not instant and atomic operations, and during that time you have at least one of the following situations:</p>
   <ul>
   <li>old code is running with the new database schema;</li>
   <li>new code is running with the old database schema.</li>
   </ul>
   <p>Let's analyse in more detail some strategies:</p>
   <ul>
   <li><b>Downtime</b>: If you could afford some downtime during migrations, than you would simply scale down your replicas to zero, run the migrations with a Kubernetes Job and then scale up your application again. <b>Pros</b>: simple, with no special requirements in your application code; no runtime errors during deployment due to different schemas. <b>Cons</b>: some minutes of downtime.</li>
   <li><b>Deploy new code, then migrate</b>: You deploy the new code, updating the images on all pods, and then, when everything is finished, you run the migration. At first this seems to works perfectly if you can make your new code support the old schema (which is not always easy). However when the new database schema is applied, you still have to deal with ActiveRecord caching the old database schema in the Ruby process (thus making an additional restart required). If you choose this trategy, you can deploy your new code and then simply connect to one of the pods and run <code>rake db:migrate</code>. <b>Pros:</b> zero downtime; deployment is very simple. <b>Cons</b>: it is very difficult to make code backward compatible; you probably need an additional restart after the migration.</li>
   <li><b>Migrate, then deploy new code</b>: This is the most common approach and it is used by Capistrano, Heroku and other CI/CD tools. The problem is that rolling out an update to many pods takes time and during that period you have the old code running with the new database schema. In order to avoid transient errors, you need to make the new schema backward compatible, so that it can run with both the old code and the new code: however it is not alwasy easy to write <i>zero downtime migrations</i> and there are many pitfalls. Also, in order to avoid additional problems, you should use a different Docker tag for each image (and not just the tag <code>latest</code>), otherwise an automatic reschedule may fetch the new image before the migration is complete. If you choose this strategy, you need to use a <i>Kubernetes Job</i> to deploy a single pod with the new image and run the migration and then, if the migration succeeds, update the image on all pods. <b>Pros</b>: common and reliable strategy. <b>Cons</b>: if you don't write backward compatible migrations, some errors may occur while the new code is being rolled out; you need to use different Docker tags for each image version if you want to prevent accidental situations where the new code runs before the migration.</li>
   </ul>
   <p>If we choose the latest solution, we must define a job like the following:</p>
   <i>config/kube/migrate.yml</i>
   <pre><code>
   apiVersion: batch/v1
   kind: Job
   metadata:
   name: migrate
   spec:
   template:
   spec:
   restartPolicy: Never
   containers:
   - name: migrate
   image: <var>username</var>/kubernetes-rails-example:latest
   command: ['rails']
   args: ['db:migrate']
   env: &hellip;
   </code></pre>
   <p>Then you can run the migration using this command:</p>
   <pre><code>
   kubectl apply -f config/kube/migrate.yml
   </code></pre>
   <p>Then you can see the status of the migration:</p>
   <pre><code>
   kubectl describe job migrate
   </code></pre>
   <p>The above command also displays the name of the pod where the migration took place. You can then see the logs:</p>
   <pre><code>
   kubectl logs <var>pod-name</var>
   </code></pre>
   <p>When the job is completed you can delete it, so that you free the resources and you can run it again in the future:</p>
   <pre><code>
   kubectl delete job migrate
   </code></pre>
    
   <h2 id="deploy">Continuous delivery</h2>
   <p>In the previous sections we have configured the Kubernetes cluster and deployed the code manually. However it would be useful to have a simple command to deploy new versions of your app whenever you want.</p>
   <p>Create the following file and make it executable (using <code>chmod +x deploy.sh</code>):</p>
   <i>deploy.sh</i>
   <pre><code>
   #!/bin/sh -ex
   export KUBECONFIG=~/.kube/kubernetes-rails-example-kubeconfig.yaml
   docker build -t <var>username</var>/kubernetes-rails-example:latest .
   docker push <var>username</var>/kubernetes-rails-example:latest
   kubectl create -f config/kube/migrate.yml
   kubectl wait --for=condition=complete --timeout=600s job/migrate
   kubectl delete job migrate
   kubectl delete pods -l app=rails-app
   kubectl delete pods -l app=sidekiq
   # For Kubernetes >= 1.15 replace the last two lines with the following
   # in order to have rolling restarts without downtime
   # kubectl rollout restart deployment/kubernetes-rails-example-deployment
   # kubectl rollout restart deployment/sidekiq
   </code></pre>
   <p>Then you can easiliy release a new version with this command:</p>
   <pre><code>
   ./deploy.sh
   </code></pre>
   <p>The above command executes the following steps:</p>
   <ol>
   <li>use sh as the interpreter and set options to print each command and exit on failure;</li>
   <li>build and publish the docker image;</li>
   <li>run the migrations and then wait the completion of the job and delete it;</li>
   <li>finally release the new code / image.</li>
   </ol>
   <p>Also remember that if you change the Kubernetes configuration you need to run this command:</p>
   <pre><code>
   kubectl apply -f kube/config
   </code></pre>
    
   <h2 id="monitoring">Monitoring</h2>
   <p>You need to monitor the Kubernetes cluster for various reasons, for example:</p>
   <ul>
   <li>understand the resource usage and scale the cluster accordingly;</li>
   <li>check if there are anomalies in the usage of resources, like pods that are using too many resources;</li>
   <li>check if all the pods are running properly or if there are some failures.</li>
   </ul>
   <p>Usually the Kubernetes provider already offers a <i>dashboard</i> with many useful stats, like CPU usage, load average, memory usage, disk usage and bandwidth usage across all the nodes. Usually they collect the stats using a <i>DaemonSet</i>, in a way similar to what we have previously described for logging. If you prefer, you can also install custom monitoring agents on all nodes: you can use open source products like Prometheus or services like Datadog.</p>
   <p>Other ways to monitor your application performance are:</p>
   <ul>
   <li>installing the Kubernetes <i>metrics-server</i> that stores the stats in memory and allows you to use commands like <code>kubectl top nodes/pods</code>;</li>
   <li>using stats from the load balancer;</li>
   <li>collecting synthetic metrics generated by ad-hoc requests sent from an external service to your application, for example in order to measure the response time from an external point of view;</li>
   <li>collecting stats directly from your Rails application using a gem for <i>application performance monitoring</i>, like Datadog APM or New Relic APM.</li>
   </ul>
    
   <h2 id="security">Security updates</h2>
   <p>There is a misconception that you can forget about security updates when you use containers. That is not true. Even if Docker and containers add an additional layer of isolation, in particular from the host and from other containers, and they are also ephemeral, which is good for security, they still need to be updated in order to avoid application exploits. Note that an attack at the application layer it is also possible when there is a security bug at a lower layer, for example in the OS or inside libraries included in the base image.</p>
   <p>If you run Rails on Kubernetes remeber to apply updates to the following layers:</p>
   <ul>
   <li><b>Kubernetes and nodes</b>: most Kubernetes providers will apply the updates for you to the underlying nodes and to Kubernetes, so that you can forget about this layer. However you may need to enable an option for automatic updates: for example, if you use DigitalOcean,  remember to go the Kubernetes settings from the dashboard and enable the automatic updates option.</li>
   <li><b>Docker and containers</b>: you need to keep your containers updated. In particular make sure that you are using an updated version of the base image. If you use Ruby as the base image, use a tag like <code>2.5</code> instead of <code>2.5.1</code>, so that you don't forget to increase the patch version when there is a new patch available. However that is not enough: when a new OS patch is available, the Ruby maintainers release a new version of the image, with the same tag (for example the image with tag <code>2.5</code> is not always the same). This means that you should ckeck Docker Hub frequently to see if the base image has received some updates (or subscribe to the official security mailing lists for Ruby, Ubuntu, etc.): if there are new updates, build your image again and deploy.</li>
   <li><b>Rails application and dependencies</b>: remember to update the versions of Ruby, Rails, Gems and Yarn packages used by your application, and any other dependencies.</li>
   <li><b>Other</b>: you also need to update the database and other services outside Kubernetes. Usually it is useful to use managed databases so that your provider applies the security patches automatically and you can forget about this layer.</li>
   </ul>
   <p>Basically, if you use managed services (for Kubernetes and database) and you deploy your application frequently, you don't need to do anything special: just keep your Rails app updated. However, if you don't release your application frequently, remember to rebuild the image and don't run your application for months on an outdated base image.</p>
    
   <h2 id="conclusion">Conclusion</h2>
   <p>We have covered all the aspects required for deploying a Ruby on Rails application in production using Kubernetes.</p>
   <p>Scaling the application or updating the configuration across hundreds of nodes is now a simple operation that can be managed by a single DevOp. Thanks to the widespread support for Kubernetes you also get a better pricing and portability, compared to PaaS solutions like Heroku.</p>
   <p>Remember that in order to achieve availability and world-scale scalability you need to avoid bottlenecks and single points of failure, in particular:</p>
   <ul>
   <li><b>the load balancer</b>, when it is a simple server, may become a bottleneck; you can use better hardware if available, but finally you will have to use <i>Round-Robin DNS</i> to increase capacity, by distributing the clients over different load balancers and deployments; if you use a global network like CloudFlare, they can even perform health checks on your load balancers, protect them from DDoS attacks and cache most requests;</li>
   <li><b>the database</b> hosted on a single server may become a bottleneck; you can use better hardware and <i>hot standby</i> servers, but finally you may have to move to a DBMS that supports <i>sharding</i>, meaning that the data is distributed automatically across different database instances, each one managing a range of keys; the database clients (e.g. inside your Rails app) first query a server in the database cluster to understand the current cluster configuration and then query the correct database instances directly, thus avoiding any kind of bottleneck; moreover each <i>shard</i> is usually replicated in order to preserve data in case of hardware failures, and thus it is called a <i>sharded replica</i>; strategies similar to what we have described are provided for example by <i>MongoDB</i> and <i>Redis Cluster</i> and there are many managed solutions available on the market.</li>
   </ul>
    


