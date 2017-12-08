module Client
  def logger
    @logger
  end

  #
  # login
  #
  # login to the navi-cloud and get the authentication token
  #
  def login
    provider_url = "http://localhost:3008/oauth/token"
    @token = HTTParty.post(provider_url,
                  body: {
                    client_id: config["uid"], # get from sso_web application
                    client_secret: config["secret_key"],
                    grant_type: "client_credentials"
                  }
                 )['access_token']
  end

  #
  # imap_connection
  #
  # connect the app with imap server
  #
  def imap_connection(server, username, password)
    # connect to IMAP server
    imap = Net::IMAP.new server, ssl: true, certs: nil, verify: false

    Net::IMAP.debug = @net_imap_debug

    # http://ruby-doc.org/stdlib-2.1.5/libdoc/net/imap/rdoc/Net/IMAP.html#method-i-capability
    capabilities = imap.capability

    @logger.debug("imap capabilities: #{capabilities.join(',')}") if @debug

    unless capabilities.include? "IDLE"
      @logger.info "'IDLE' IMAP capability not available in server: #{server}"
      imap.disconnect
      exit
    end

    # login
    imap.login username, password

    # return IMAP connection handler
    imap
  end

  #
  # retrieve_emails
  #
  # retrieve any mail from a folder, followin specified serach condition
  # for any mail retrieved call a specified block
  #
  def retrieve_emails(imap, search_condition, folder, &process_email_block)

    # select folder
    imap.select folder

    message_ids = imap.search(search_condition)

    if @debug
      if message_ids.empty?
        @logger.debug "\nno messages found.\n"
        return
      else
        @logger.debug "\nProcessing #{message_ids.count} mails.\n"
      end
    end

    message_ids.each_with_index do |message_id, i|
      # fetch all the email contents
      data = imap.fetch(message_id, "RFC822")

      data.each do |d|
        msg = d.attr['RFC822']
        # instantiate a Mail object to avoid further IMAP parameters nightmares
        mail = Mail.read_from_string msg

        # call the block with mail object as param
        start = (i == 0)
        last = (i == message_ids-1)
        process_email_block.call mail, start, last

        # mark as read
        if @mark_as_read
          imap.store(message_id, "+FLAGS", [:Seen])
        end
      end
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
        retrieve_emails(imap, search_condition, folder) { |mail| process_email mail }
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

  def process_email(mail, start, last)
    meta = Hash.new
    custom_uid = (Time.now.to_f * 1000).to_s + "_" + mail.__id__.to_s

    meta["from"] = mail.from.first
    meta["to"] = mail.to.join(";") unless mail.to.nil?
    meta["cc"] = mail.cc.join(";") unless mail.cc.nil?
    meta["subject"] = mail.subject
    meta["date"] = mail.date.to_s

    if mail.multipart?
      for i in 0...mail.parts.length
        m = @local_flag  ? download_local(mail, custom_uid) : download_s3(mail, custom_uid)
        meta.merge!(m) unless m.nil?
      end
    else
      m = @local_flag ? download_local(mail, custom_uid) : download_s3(mail, custom_uid)
      meta.merge!(m) unless m.nil?
    end

    meta_file_path = save(meta, "meta/#{custom_uid}")
    pid = Process.spawn(@cmd+" -f=#{meta_file_path} -t=#{@token}")

    HTTPService::NaviAI.start(start, last)
  end

  private

  def save(data={}, filename)
    download_path = config['download_path']
    filepath = download_path + filename + ".yml"

    mkdir_if_not_exist(filepath)

    File.write(filepath, data.to_yaml)
    return filepath
  end

  def encrypt(data)
    Base64.encode64(data)
  end

  def mkdir_if_not_exist(filepath)
    dirname = File.dirname(filepath)
    unless File.directory?(dirname)
      FileUtils.mkdir_p(dirname)
    end
  end

  def time_now
    Time.now.utc.iso8601(3)
  end

  def shutdown(imap)
    imap.idle_done
    imap.logout unless imap.disconnected?
    imap.disconnect

    @logger.info "#{$0} has ended (crowd applauds)"
    exit 0
  end

  def config
    YAML.load_file('/var/navi/config.yml')
  end
end
