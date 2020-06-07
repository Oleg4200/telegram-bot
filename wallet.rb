# frozen_string_literal: true

require_relative 'db_pg'
require_relative 'telegram_bot'

class Wallet
  def buy_coin(coin, message, chat_id, coin_price)
    quantity = message.text.to_f.round(4)
    last_wallet_id
    user_points(chat_id)

    user_have_coin = DBPG::CON.exec "SELECT * FROM Wallets WHERE User_Id = #{chat_id} AND Coin = '#{coin}'"

    if quantity * coin_price <= @points_quantity
      @points_quantity -= quantity * coin_price
      if !user_have_coin.values.empty?
        DBPG::CON.exec "UPDATE Wallets SET Quantity = #{user_have_coin.values[0][2].to_f.round(4) + quantity} WHERE User_Id = #{chat_id} AND Coin = '#{coin}'"
      else
        DBPG.new.insert_wallets(@last_id + 1, coin, quantity, chat_id)
      end
      DBPG::CON.exec "UPDATE Wallets SET Quantity = #{@points_quantity} WHERE User_Id = #{chat_id} AND Coin = 'Point'"
      Transaction.new.add_transaction('buy', coin, message.text.to_f.round(4), coin_price, message.chat.id)
      TelegramBot.new.bot.api.send_message(chat_id: message.chat.id, text: "You just buy #{message.text} #{coin}")
    else
      TelegramBot.new.bot.api.send_message(chat_id: message.chat.id, text: 'You don`t have enough points')
    end
  end

  def show_wallet(_message)
    TelegramBot.new.bot.listen do |message|
      arr_name_btn = ['Sell coin', 'Back to home']
      @markup = TelegramBot.new.iterate_btn(arr_name_btn)

      TelegramBot.new.coin_message if message.text == 'Back to home'
      sell_coin(message) if message.text == 'Sell coin'

      if message.text == 'Wallet' || message.text == 'Back to wallet'
        TelegramBot.new.bot.api.send_message(chat_id: message.chat.id, text: 'Your wallet', reply_markup: @markup)
        user_wallet = DBPG::CON.exec "SELECT * FROM Wallets WHERE User_Id = #{message.chat.id}"
        amount_usd = 0
        user_wallet.values.each do |value|
          @coin_price = CryptoBotIndex.new.parameter_api(message, value[1])
          if value[1] != 'Point'
            amount_usd += @coin_price * value[2].to_f.round(4)
            TelegramBot.new.send_message(message.chat.id, "#{value[1]} quantity - #{value[2]}, total(#{value[1]}) - #{@coin_price * value[2].to_f.round(4)}")
          else
            amount_usd += value[2].to_f.round(4)
            TelegramBot.new.send_message(message.chat.id, "#{value[1]} quantity - #{value[2]}")
          end
        end
        TelegramBot.new.send_message(message.chat.id, "Amount = #{amount_usd}")
      end
    end
  end

  def sell_coin(_message)
    TelegramBot.new.bot.listen do |message|
      kb = [
        TelegramBot::BTN.new(text: 'Back to wallet', one_time_keyboard: true)
      ]
      user_wallet = DBPG::CON.exec "SELECT * FROM Wallets WHERE User_Id = #{message.chat.id}"
      user_wallet.values.each do |value|
        kb.push(TelegramBot::BTN.new(text: (value[1]).to_s, one_time_keyboard: true)) if value[1] != 'Point'
      end
      markup = Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: kb)

      if message.text == 'Sell coin'
        TelegramBot.new.bot.api.send_message(chat_id: message.chat.id, text: 'Choose what coin you wanna sell', reply_markup: markup)
      end

      sell_current_coin(message) if TelegramBot::ARRCOIN.include?(message.text)
      show_wallet(message) if message.text == 'Back to wallet'
    end
  end

  def sell_current_coin(_message)
    TelegramBot.new.bot.listen do |message|
      if TelegramBot::ARRCOIN.include?(message.text)
        TelegramBot.new.bot.api.send_message(chat_id: message.chat.id, text: "Write quantity #{message.text} that you wanna sell")
      end
      current_quantity_coin(message)
      sell_coin(message) if message.text == 'Back to wallet'

      if message.text.to_f.round(4) <= @current_quantity && TelegramBot::ARRCOIN.include?(message.text) == false
        DBPG::CON.exec "UPDATE Wallets SET Quantity = #{@current_quantity - message.text.to_f.round(4)} WHERE User_Id = #{message.chat.id} AND Coin = '#{@coin}'"
        @coin_price = CryptoBotIndex.new.parameter_api(message, @coin)
        Transaction.new.add_transaction('sell', @coin, message.text.to_f.round(4), @coin_price, message.chat.id)
        TelegramBot.new.bot.api.send_message(chat_id: message.chat.id, text: "You just sold #{message.text} #{@coin}")
        user_points(message.chat.id)
        @sell_points_quantity = (message.text.to_f.round(4) * @coin_price) + @points_quantity
        DBPG::CON.exec "UPDATE Wallets SET Quantity = #{@sell_points_quantity} WHERE User_Id = #{message.chat.id} AND Coin = 'Point'"
      end
    end
  end

  private

  def last_wallet_id
    wallet = DBPG::CON.exec 'SELECT * FROM Wallets'
    @last_id = 0
    wallet.each do |row|
      if row['id'].to_i > @last_id
        @last_id = row['id'].to_i
      end
    end
  end

  def current_quantity_coin(message)
    user_wallet = DBPG::CON.exec "SELECT * FROM Wallets WHERE User_Id = #{message.chat.id} AND Coin = '#{message.text}'"
    user_wallet.values.each do |value|
      @current_quantity = value[2].to_f.round(4)
      @coin = value[1]
    end
  end

  def user_points(chat_id)
    user_points = DBPG::CON.exec "SELECT * FROM Wallets WHERE User_Id = #{chat_id} AND Coin = 'Point'"
    @points_quantity = user_points.values[0][2].to_f.round(4)
  end
end
