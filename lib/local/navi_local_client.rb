require Gem::Specification.find_by_name("navi_client").gem_dir+"/lib/client"
module NaviClient
  class Local
    include Client
    def initialize(sso_web_url = 'http://localhost:3008')
      # flag to print Ruby library debug info (very detailed)
      @net_imap_debug = false

      # flag to mark email as read after gets downloaded.
      @mark_as_read = false

      # flag to turn on/off debug mode.
      @debug = false

      # override the log file
      mkdir_if_not_exist(config['client_log_file'])
      @logger = Logger.new(config['client_log_file'])

      # sso_web (authentication) config.
      @sso_web_url = sso_web_url
      # authentication token received from sso_web used to authenticate the request to database_api
      @token = nil

      # client_type
      @client_type = "local"
    end

    #
    # login
    #
    # login to the navi-cloud and get the authentication token
    #
    def login
      url = "#{@sso_web_url}/oauth/token"
      provider_url = url
      @token = HTTParty.post(provider_url,
                             body: {
                               client_id: config["uid"], # get from sso_web application
                               client_secret: config["secret_key"],
                               grant_type: "client_credentials"
                             }
                            )['access_token']
    end

    def download(message, custom_uid)
      download_path = config['download_path']
      if ['text/plain', 'text/html'].include? message.mime_type

        h = Hash.new
        out_file = download_path + message.mime_type + "/"+custom_uid
        mkdir_if_not_exist(out_file)

        File.open(out_file, 'w') { |file| file.write(encrypt(message.decoded)) }
        key = message.mime_type.split("/").join("_")

        h[key] = out_file
        return h
      end
    end

    def save(data={}, filename)
      download_path = config['download_path']
      filepath = download_path + filename + ".yml"

      mkdir_if_not_exist(filepath)

      File.write(filepath, data.to_yaml)
      return filepath
    end

    def mkdir_if_not_exist(filepath)
      dirname = File.dirname(filepath)
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end
    end

    #
    # idle_loop
    #
    # check for any further mail with "real-time" responsiveness.
    # retrieve any mail from a folder, following specified search condition
    # for any mail retrieved call a specified block
    #
    def idle_loop(imap, search_condition, folder, server, username, password)

      @logger.info "\nwaiting new mails (IDLE loop)..."

      loop do
        begin
          imap.select folder
          imap.idle do |resp|

            # You'll get all the things from the server. For new emails (EXISTS)
            if resp.kind_of?(Net::IMAP::UntaggedResponse) and resp.name == "EXISTS"

              @logger.debug resp.inspect if @debug
              # Got something. Send DONE. This breaks you out of the blocking call
              imap.idle_done
            end
          end

          # We're out, which means there are some emails ready for us.
          # Go do a search for UNSEEN and fetch them.
          filenames = []
          retrieve_emails(imap, search_condition, folder) { |mail| filenames << process_email(mail)}
          self.send_request(filenames)

          @logger.debug "Process Completed." if @debug

        rescue SignalException => e
          # http://stackoverflow.com/questions/2089421/capturing-ctrl-c-in-ruby
          @logger.info "Signal received at #{time_now}: #{e.class}. #{e.message}"
          shutdown imap

        rescue Net::IMAP::Error => e
          @logger.error "Net::IMAP::Error at #{time_now}: #{e.class}. #{e.message}"

          # timeout ? reopen connection
          imap = imap_connection(server, username, password) #if e.message == 'connection closed'
          @logger.info "reconnected to server: #{server}"

        rescue Exception => e
          @logger.error "Something went wrong at #{time_now}: #{e.class}. #{e.message}"

          imap = imap_connection(server, username, password)
          @logger.info "reconnected to server: #{server}"
        end
      end
    end

    def config
      YAML.load_file(ENV['HOME'] + '/.navi/config.yml').with_indifferent_access
    end
  end
end
