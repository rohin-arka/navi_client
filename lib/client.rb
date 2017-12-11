require "net/imap"
require "mail"
require "time"

require 'base64'
require 'fileutils'
require 'yaml'

require "pry"
require "logger"

require "httparty"
require "http_service/naviai"

module Client
  def logger
    @logger
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
        process_email_block.call mail

        # mark as read
        if @mark_as_read
          imap.store(message_id, "+FLAGS", [:Seen])
        end
      end
    end
  end

  def process_email(mail)
    meta = Hash.new
    custom_uid = (Time.now.to_f * 1000).to_s + "_" + mail.__id__.to_s

    meta["from"] = mail.from.first
    meta["to"] = mail.to.join(";") unless mail.to.nil?
    meta["cc"] = mail.cc.join(";") unless mail.cc.nil?
    meta["subject"] = mail.subject
    meta["date"] = mail.date.to_s

    if mail.multipart?
      for i in 0...mail.parts.length
        m = download(mail, custom_uid)
        meta.merge!(m) unless m.nil?
      end
    else
      m = download(mail, custom_uid)
      meta.merge!(m) unless m.nil?
    end

    save(meta, "meta/#{custom_uid}")
  end

  def encrypt(data)
    Base64.encode64(data)
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
end
