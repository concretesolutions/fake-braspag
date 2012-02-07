require "bundler/setup"

Bundler.require 

$:.unshift File.dirname(File.expand_path(__FILE__)) + "/lib"

module FakeBraspag
  AUTHORIZE_URI = "/webservices/pagador/Pagador.asmx/Authorize"
  CAPTURE_URI   = "/webservices/pagador/Pagador.asmx/Capture"

  module CreditCards
    AUTHORIZE_OK                 = "5340749871433512"
    AUTHORIZE_DENIED             = "5558702121154658"
    AUTHORIZE_AND_CAPTURE_OK     = "5326107541057732"
    AUTHORIZE_AND_CAPTURE_DENIED = "5430442567033801"
    CAPTURE_OK                   = "5277253663231678"
    CAPTURE_DENIED               = "5473598178407565"
  end

  module Authorize
    module Status
      AUTHORIZED = "1"
      DENIED     = '2'
    end
  end

  module Capture
    module Status
      CAPTURED = "0"
      DENIED   = "2"
    end
  end

  class App < Sinatra::Base
    class << self
      attr_reader :received_requests

      def save_request(order_id, card_number)
        @received_requests ||= {}
        @received_requests[order_id] = card_number
      end

      def clear_requests
        @received_requests.clear
      end
    end

    post AUTHORIZE_URI do
      save_request if authorize_with_success?
      <<-EOXML
        <?xml version="1.0" encoding="utf-8"?>
        <PagadorReturn xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                       xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                       xmlns="https://www.pagador.com.br/webservice/pagador">
          <amount>5</amount>
          <message>Transaction Successful</message>
          <authorisationNumber>733610</authorisationNumber>
          <returnCode>7</returnCode>
          <status>#{authorize_status}</status>
          <transactionId>#{params[:order_id]}</transactionId>
        </PagadorReturn>
      EOXML
    end

    post CAPTURE_URI do
      <<-EOXML
        <?xml version="1.0" encoding="utf-8"?>
        <PagadorReturn xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                       xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                       xmlns="https://www.pagador.com.br/webservice/pagador">
          <amount>2</amount>
          <message>Approved</message>
          <returnCode>0</returnCode>
          <status>#{capture_status}</status>
        </PagadorReturn>
      EOXML
    end

    private
    def save_request
      self.class.save_request params[:order_id], params[:card_number]
    end

    def authorize_with_success?
      authorize_status == Authorize::Status::AUTHORIZED
    end

    def authorize_status
      case params[:card_number]
      when CreditCards::AUTHORIZE_OK; Authorize::Status::AUTHORIZED
      when CreditCards::AUTHORIZE_DENIED; Authorize::Status::DENIED
      when CreditCards::AUTHORIZE_AND_CAPTURE_OK; Capture::Status::CAPTURED
      when CreditCards::AUTHORIZE_AND_CAPTURE_DENIED; Capture::Status::DENIED
      when CreditCards::AUTHORIZE_OK, CreditCards::CAPTURE_OK, CreditCards::CAPTURE_DENIED; Authorize::Status::AUTHORIZED
      end
    end

    def capture_status
      case self.class.received_requests[params[:order_id]]
      when CreditCards::CAPTURE_OK; Capture::Status::CAPTURED
      when CreditCards::CAPTURE_DENIED; Capture::Status::DENIED
      end
    end

    configure do
      set :show_expections, false
    end
  end
end
