
library(shiny)
library(plotly)
library(dplyr)
library(lubridate)
library(htmlwidgets)
library(leaflet)
library(leaflet.extras)
library(leaflet.esri)

library(geojsonio)
library(jsonlite)
library(RCurl)

source("sm_data.R")

# t <- list(
#   family = "Tahoma",
#   size = 14,
#   color = 'black')

tx <- list(
  family = "Tahoma",
  size = 12,
  color = 'black')

death_label <- list(visible=TRUE, 
                    title=
                      list(text = "Daily Deaths"
                           ))

case_label <- list(visible=TRUE, 
                    title=
                      list(text = "Daily Cases"
                           ))


shinyServer(function(input, output, session) {
  
  output$deathsplot <- renderPlotly({
    
    p <- dat %>% 
      plot_ly(source='deaths') %>% 
      add_trace(type='bar',  
                x=~Date, 
                y=~Daily_Deaths, 
                text = paste(dat$Date,"<br>",
                             dat$Daily_Deaths, "Deaths<br><i>", 
                             dat$Daily_Deaths_cum, "Cumulative deaths</i>" ),
                hoverinfo = "text",
                marker=list(color='lightgrey', width=1)) %>% 
      add_lines(x=~Date, y=~Daily_Deaths_ma, hoverinfo = "none") %>% 
      layout(showlegend = FALSE, yaxis=death_label)
   
    
    # make event lines
    event_cols <- brewer.pal(n=5, 'Dark2')
    tmp <- dat %>% dplyr::filter(!is.na(dat$Types_EO))
    event_lines <- lapply(1:nrow(tmp), function(i) {
      list(type = 'line', 
           line = list(color=event_cols[as.numeric(tmp$Types_EO[i])], 
                       dash='dash',  width=1),
           opacity = 1, x0=tmp$Date[i], x1=tmp$Date[i], 
           xref='x', y0=0.05, y1=1, yref='paper')
    })
    
    tmp_data <- tmp %>% mutate(dummy = max(dat$Daily_Deaths, na.rm=TRUE))
    p %>% 
      add_trace(type = 'bar', 
                x=~Date, 
                y=~dummy,
                marker = list(color='black'),
                text = tmp$Types_EO, 
                hoverinfo = 'text', 
                data = tmp_data,
                opacity=0) %>%
      layout(shapes = event_lines, 
             xaxis = list(title=""), showlegend=FALSE) %>% 
      event_register("plotly_click")
  })
  
  
  
  
  output$casesplot <- renderPlotly({
    
    p <- dat %>% 
      plot_ly(source='cases') %>% 
      add_trace(type='bar',  
                x=~Date, 
                y=~Daily_Cases, 
                text = paste(dat$Date,"<br>",
                             dat$Daily_Cases, "Cases<br><i>", 
                             dat$Daily_Cases_cum, "Cumulative cases</i>" ),
                hoverinfo = "text",
                marker=list(color='lightgrey', width=1)) %>% 
      add_lines(x=~Date, y=~Daily_Cases_ma, hoverinfo = "none") %>% 
      layout(showlegend = FALSE, yaxis=case_label)
    
    # make event lines
    event_cols <- brewer.pal(n=5, 'Dark2')
    tmp <- dat %>% dplyr::filter(!is.na(dat$Types_EO))
    event_lines <- lapply(1:nrow(tmp), function(i) {
      list(type = 'line', 
           line = list(color=event_cols[as.numeric(tmp$Types_EO[i])], 
                       dash='dash',  width=1),
           opacity = 1, x0=tmp$Date[i], x1=tmp$Date[i], 
           xref='x', y0=0.05, y1=1, yref='paper')
    })
    
    p %>% 
      add_trace(type = 'bar', 
                x=~Date, 
                y=~dummy,
                marker = list(color='black'),
                text = tmp$Types_EO, 
                hoverinfo = 'text', 
                data = tmp %>% mutate(dummy = max(dat$Daily_Cases)),
                opacity=0) %>%
      layout(shapes = event_lines, 
             xaxis = list(title="")) %>% 
      event_register("plotly_click")
    })
  
  
  observeEvent(event_data("plotly_click", source = "deaths"), {
    d = event_data("plotly_click", source = "deaths")
    cat("from death plot", d$x, '\n')
    
    policy_txt = ""
    if (d$curveNumber[1] == 2) {
      x <- d$x[1]
      tmp <- subset(dat, Date == x)
      policy_txt = tmp$Details_1[1]
    }
    
    updateTextInput(session, "hidden", value = sprintf("XXXdeaths|%s|%s", d$x, policy_txt))
    
  })

  observeEvent(event_data("plotly_click", source = "cases"), {
    d = event_data("plotly_click", source = "cases")
    cat("from casesh plot", d$x, '\n')
    
    policy_txt = ""
    if (d$curveNumber[1] == 2) {
      x <- d$x[1]
      tmp <- subset(dat, Date == x)
      policy_txt = tmp$Details_1[1]
    }
    
    updateTextInput(session, "hidden", value = sprintf("XXXcases|%s|%s", d$x, policy_txt))
  })
  
  
  output$click <- renderText({
    clicked_info <- input$hidden
    clicked_comps <- strsplit(clicked_info, "\\|")[[1]]
    if (is.na(clicked_comps[3]) || is.null(clicked_comps[3]))
      return("FOO")
    else 
      return(clicked_comps[3])
  })
  

  observeEvent(input$tabs, {
    val = input$hidden
    if (input$tabs == 'Deaths')
      newval <- gsub("XXXcases", "XXXdeaths", val)
    else 
      newval <- gsub("XXXdeaths", "XXXcases", val)
    updateTextInput(session, "hidden", value = newval)
  })
  
  
  output$map1 <- renderLeaflet({
    cat("We're here for map1\n")
    clicked_info <- input$hidden
    clicked_comps <- strsplit(clicked_info, "\\|")[[1]]
    clicked_plot = clicked_comps[1]
    clicked_date = clicked_comps[2]
    
    date_comps <- strsplit(clicked_date, "-")[[1]]
    if (length(date_comps) != 3) return(NULL)
    mm <- month.name[as.integer(date_comps[2])]
    col_name <- sprintf("%s_%d_%s", mm, as.integer(date_comps[3]), date_comps[1])
    cat(col_name, '\n')
    
    todays_idx = which(names(dat_cases) == col_name)
    yesterday_idx = todays_idx - 1

    
    if (clicked_plot == 'cases') {
      dat_to_use <- dat_cases
      dat_to_use$pdat <- dat_cases[[todays_idx]] - dat_cases[[yesterday_idx]]
      dat_to_use$pdat[ dat_to_use$pdat < 0] <- 0
      pal = colorQuantile("YlGn",dat_to_use$pdat, n=5)
      #pal <- myQuantile(dat_to_use$pdat, 5, "YlGn")
      #pal = colorBin("OrRd", jitter(dat_to_use[[col_name]]), bins=9)
    } else {
      dat_to_use <- dat_deaths
      dat_to_use$pdat <- dat_deaths[[todays_idx]] - dat_deaths[[yesterday_idx]]
      dat_to_use$pdat[ dat_to_use$pdat < 0] <- 0
      pal = colorQuantile("Reds", dat_to_use$pdat, n=5)
      #pal <- myQuantile(dat_to_use$pdat, 5, "Reds")
      #pal = colorBin("Reds", jitter(dat_to_use[[col_name]]), bins=9)
    }
    if (!(col_name %in% names(dat_to_use))) 
      return(NULL)
    
    m <- leaflet(dat_to_use) %>%
      addEsriBasemapLayer(esriBasemapLayers$Gray) %>%
      setView(-72.699997, 41.599998, 8) %>%
      addPolygons(stroke=TRUE, weight=1, color='grey', fillOpacity = 0.8, 
                  popup = paste0("<b>Town:</b> ",dat_to_use$TOWN, "<br>","<b>Total</b>: ", dat_to_use[["pdat"]]),
                  smoothFactor = 0.2, fillColor = pal(dat_to_use[["pdat"]])) %>% 
      addLegend(pal = pal, values = dat_to_use[["pdat"]], opacity=1, title = col_name) 
    m
  })
  
  
})

