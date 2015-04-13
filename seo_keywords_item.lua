local http = require "socket.http"
local cjson = require "cjson"

patterns = function (is_mobile)
	local tbody_pattern
	local item_pattern
	local link_pattern
	local copy_txt_pattern
	local review_num_pattern
	local price_pattern
	local point_pattern
	
	if is_mobile == "1" then
		tbody_pattern = "<div%s+data%-ratUnit=\"true\"%s+class=\"resultItem%s+displayedItem\">.*<script%s+id=\"spmallAsuraku_viewTemplate\""
		item_pattern = "<div%s+data%-ratUnit=\"true\"%s+class=\"resultItem%s+displayedItem\">.-<li%s+class=\"itemPrice\">.-</div>"
		link_pattern = "<dt%s+class=\"itemName\">.-<a%s+href=\"http://item.rakuten.co.jp/(%w+)/([^/]-)/\"%s+target=\"_top\">(.-)</a>"
		copy_txt_pattern = "<dd%s+class=\"itemTxt\">(.-)</dd>"
		review_num_pattern = "<li%s+class=\"itemIcnRvw\">.-<a%s+href=\"http://review.rakuten.co.jp/.-\">(%d+)件"
		price_pattern = "<li%s+class=\"itemPrice\">.-([,0-9]+)円</li>"
		point_pattern = "<li%s+class=\"itemPoint\">.-(%d+)倍</li>"
	else
		tbody_pattern = "<div%s+class=\"searchAccuracyMeasurement\".*<div%s+id=\"rsrPagerSect\">"
		item_pattern = "<div%s+class=\"searchAccuracyMeasurement\".-あす楽締切時間を表示"
		link_pattern = "<div%s+class=\"rsrSResultItemTxt\">.-<a%s+href=\"http://item.rakuten.co.jp/(%w+)/([^/]-)/\">(.-)</a>"
		copy_txt_pattern = "<p%s+class=\"copyTxt\">(.-)</p>"
		review_num_pattern = "<span%s+class=\"txtIconReviewNum\">.-<a%s+href=\"http://review.rakuten.co.jp/.-\">(%d+)件"
		price_pattern = "<p%s+class=\"price\">.->([,0-9]+)<span>.-円</span>"
		point_pattern = "<p%s+class=\"point\">.-(%d+)倍</p>"
	end
	
	return tbody_pattern, item_pattern, link_pattern, copy_txt_pattern, review_num_pattern, price_pattern, point_pattern
end

run = function (params)
	local data = cjson.decode(params)
	local headers = {}
	local tbody_pattern, item_pattern, link_pattern, copy_txt_pattern, review_num_pattern, price_pattern, point_pattern = patterns(data.is_mobile)
	local page_limit
	if data.is_mobile == "1" then
		headers["User-Agent"] = "Mozilla/5.0 (iPhone; U; CPU iPhone OS 3_0 like Mac OS X; en-us) AppleWebKit/528.18 (KHTML, like Gecko) Version/4.0 Mobile/7A341 Safari/528.16"
		page_limit = 10
	else
		headers["User-Agent"] = "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:32.0) Gecko/20100101 Firefox/32.0"
		page_limit = 45
	end
	
	local t = {}
	local response, code = http.request{url = data.url, headers = headers, sink = ltn12.sink.table(t)}
	local result = {}
	result.keyword = data.keyword
	local date_table = os.date('*t')
	result.date = string.format("%4d-%02d-%02d", date_table.year, date_table.month, date_table.day)
	
	if code == 200 then
		local c = table.concat(t)
		local tbody = string.match(c, tbody_pattern)
		if tbody == nil then
			return nil
		end
		
		local count = 0
		for tr in string.gmatch(tbody, item_pattern) do
			local item = {}
			
			count = count + 1
			if data.is_mobile == "1" then
				item.rank = page_limit * (data.page_num - 1) + count
			else
				local item_pos, page_num = string.match(tr, "<div%s+class=\"searchAccuracyMeasurement\"%s+itemPosition=\"(%d+)\"%s+pageNumber=\"(%d+)\".-</div>")
				item.rank = page_limit * (page_num - 1) + item_pos
			end
			item.shop_name, item.item_code, item.title = string.match(tr, link_pattern)
			item.copy_txt = string.match(tr, copy_txt_pattern)
			item.review_num = string.match(tr, review_num_pattern)
			item.price = string.gsub(string.match(tr, price_pattern), ',', '')
			item.point = string.match(tr, point_pattern)
			if string.match(tr, "送料込") then
				item.free_shipping = 1
			end
			table.insert(result, item)
		end
	end
	return cjson.encode({result = result})
end

print(run('{"is_mobile":"1","url":"http://search.rakuten.co.jp/search/mall/0055/-/p.2","keyword":"0055","page_num":"2"}'))