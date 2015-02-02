local http = require "socket.http"
local cjson = require "cjson"

run = function (params)
	local data = cjson.decode(params)
	local headers = {}
	headers["User-Agent"] = "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:10.0) Gecko/20100101 Firefox/10.0"
	local t = {}
	local response, code, head = http.request{url = data.url, headers = headers, sink = ltn12.sink.table(t)}
	local trades = {}

	if code == 200 then
		local c = table.concat(t)
		local tbody = string.match(c, "<tbody>%s*(.-)%s*</tbody>")
		if tbody == nil then
			return nil
		end
		
		local year = os.date('*t').year
		for tr in string.gmatch(tbody, "<tr[^>]*>(.-)</tr>") do
			local trade = {}
			trade.addr = string.match(tr, "<td class=\"addr\">(.-)</td>")
			local qty = string.match(tr, "<td class=\"qty\">(%d+)</td>")
			trade.quantity = qty and qty or 1
			trade.price = string.gsub(string.match(tr, "<td class=\"price\">([%d,]+).*</td>"), ",", "")
			if string.match(tr, "<td class=\"name\">.-<a href=\"http://item.rakuten.co.jp/[%w-_]+/[%w-_]+/\" target=\"_top\">.-</a>.-</td>") then
				trade.item_code, trade.name = string.match(tr, "<td class=\"name\">.-<a href=\"http://item.rakuten.co.jp/[%w-_]+/([%w-_]+)/\" target=\"_top\">(.-)</a>.-</td>")
			elseif string.match(tr, "<td class=\"name\"><span>.-</span>") then
				trade.name = string.match(tr, "<td class=\"name\"><span>(.-)</span>")
			end
			trade.order_no = string.match(tr, "<td class=\"o_no\">([%w-_*]+)</td>")
			if string.match(tr, "<td class=\"date\">%d+月%d+日[^%d]*%d+時%d+分</td>") then
				local month, day, hour, min = string.match(tr, "<td class=\"date\">(%d+)月(%d+)日[^%d]*(%d+)時(%d+)分</td>")
				trade.order_date = string.format("%4d-%02d-%02d %02d:%02d:00", year, month, day, hour, min)
				if os.time({year=year, month=month, day=day, hour=hour, min=min}) > os.time() then
					trade.order_date = string.format("%4d-%02d-%02d %02d:%02d:00", year - 1, month, day, hour, min)
				end
			end
			--reverse
			table.insert(trades, 1, trade)
		end
	end
	return cjson.encode({result = trades})
end

print(run('{"url":"http://www.rakuten.ne.jp/gold/diana/orders/live.html","shop_id":"190446"}'))