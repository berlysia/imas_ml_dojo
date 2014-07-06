class Dojo
  constructor: (dojo) ->
    @userid = dojo.userid
    @username = dojo.username
    @unitname = dojo.unitname
    @level = dojo.level
    @dispvalue = dojo.dispvalue
    @comment = dojo.comment

Vue.directive 'check-current-key', (value)->
  if value[0] == value[1]
    @el.parentNode.classList.add('disabled')
  else
    @el.parentNode.classList.remove('disabled')

$ ->
  content: new Vue
    el: "#content"
    paramAttributes: ['page','each_page_length','level_bound','value_bound','order']
    data:
      dojos: []
      page: 0
      page_max: 0
      pagenator: []
      loading: false
    methods:
      addDojo: (dojo) ->
        d = new Dojo(dojo)
        @$data.dojos.push(d)
      fetchDojos: (idx) ->
        return if @$data.loading
        @$data.loading = true
        url = "/api/getdojos?offset=0&page=#{parseInt(idx)}&length=#{@each_page_length}&level_bound=#{@level_bound}&value_bound=#{@value_bound}&order=#{@order}"
        console.log url
        $.getJSON url, (dojos) =>
          @$data.dojos = dojos.map((dojo)->new Dojo(dojo))
          @$data.loading = false
        .fail (xhr,stat,err) ->
          @$data.loading = false
      listPagenation: (idx) ->
        return if parseInt(idx) == @$data.page
        @$data.page = parseInt(idx)
        @updatePagenator(idx)
        @fetchDojos(idx)
      updatePagenator: (idx) ->
        if @$data.page_max < 5
          @pg_from = 0
          @pg_size = @$data.page_max + 1
        else if @$data.page < 3
          @pg_from = 0
          @pg_size = 5
        else if @$data.page_max - 2 < @$data.page
          @pg_from = @$data.page_max - 4
          @pg_size = 5
        else
          @pg_from = @$data.page - 2
          @pg_size = 5

        pagenator = []
        for i in [0...@pg_size]
          pagenator.push @pg_from+i
        @$data.pagenator = pagenator
      onPagenatorClick: (idx,evt,toTop) ->
        evt.preventDefault()
        @listPagenation(idx)
        window.history.pushState('','',"/list?page=#{idx}")
        $('body').animate({scrollTop:0},0) if toTop
    created: ->
      @$data.page = parseInt(@page)
      url = "/api/getdojos?offset=0&length=#{@each_page_length}&level_bound=#{@level_bound}&value_bound=#{@value_bound}&order=#{@order}&page_max=true"
      $.getJSON url, (page_max) =>
        @$data.page_max = parseInt(page_max)
        @updatePagenator(@$data.page)
        @fetchDojos(@$data.page)
      .fail (xhr,stat,err) ->
