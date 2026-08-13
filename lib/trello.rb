# frozen_string_literal: true

class Trello
  class ApiError < StandardError
    attr_reader :status

    def initialize(message, status)
      @status = status
      super(message)
    end
  end

  BASE_URL = 'https://api.trello.com/1'

  def initialize(api_key:, token:)
    @api_key = api_key
    @token = token
    raise ArgumentError, 'Missing API key' if api_key.blank?
    raise ArgumentError, 'Missing token' if token.blank?
  end

  def member_me
    get('/members/me')
  end

  def boards
    get('/members/me/boards', fields: 'id,name', filter: 'open')
  end

  def board_lists(board_id)
    get("/boards/#{board_id}/lists", fields: 'id,name,closed')
  end

  def open_cards(board_id)
    get("/boards/#{board_id}/cards", filter: 'open', fields: 'id,name,desc,idList')
  end

  def board_comment_actions(board_id)
    get("/boards/#{board_id}/actions", filter: 'commentCard', limit: 1000)
  end

  def card_comment_actions(card_id)
    get("/cards/#{card_id}/actions", filter: 'commentCard', limit: 1000)
  end

  def card(card_id)
    get("/cards/#{card_id}", fields: 'id,name,desc,idList')
  end

  def create_webhook(board_id:, callback_url:)
    post('/webhooks', callbackURL: callback_url, idModel: board_id, active: true)
  end

  def delete_webhook(webhook_id)
    delete("/webhooks/#{webhook_id}")
  end

  def move_card(card_id, list_id)
    put("/cards/#{card_id}", idList: list_id)
  end

  private

  def get(path, params = {})
    request(:get, path, params)
  end

  def post(path, body = {})
    request(:post, path, {}, body)
  end

  def put(path, body = {})
    request(:put, path, {}, body)
  end

  def delete(path)
    request(:delete, path)
  end

  def request(method, path, params = {}, body = {})
    options = {
      query: params.merge(key: @api_key, token: @token),
      timeout: 10
    }

    unless body.empty?
      options[:headers] = { 'Content-Type' => 'application/json' }
      options[:body] = body.to_json
    end

    response = HTTParty.public_send(method, "#{BASE_URL}#{path}", options)
    return response.parsed_response if response.success?

    raise_api_error(response)
  end

  def raise_api_error(response)
    message = response.parsed_response.presence || response.body.presence || response.message
    raise ApiError.new(message, response.code)
  end
end
