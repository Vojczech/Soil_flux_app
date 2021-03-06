# load up the packages
library(shiny)
library(shinythemes)
library(readr)
library(tidyverse)
library(Rmisc)
library(tools)
require(showtext)
library(hrbrthemes)
library(svglite)

# download a webfont
font_add_google(name = "Roboto Condensed", family = "Roboto Condensed",
                regular.wt = 400, bold.wt = 700)
showtext_auto()

function(input, output) {
  
  dataset_flux <- reactive({
    validate(
      need(input$csv_data != "", "Please upload a csv file with soil flux data")
    )
    infile = input$csv_data  
    
    if (is.null(infile))
      return(NULL)
    
    read_delim(infile$datapath, delim = ",", escape_double = FALSE, col_names = TRUE, na = "NA", trim_ws = TRUE, locale = locale( tz = "UTC"))
  })

# get name of uploaded file
  file_name <- reactive({
    inFile <- input$csv_data
    
    if (is.null(inFile))
      return(NULL) else return (tools::file_path_sans_ext(inFile$name))
  })
  
# merge daytime columns  
  dataset_date_joined <- reactive({
    dataset_flux <- dataset_flux()
    dataset_date_joined <- mutate(dataset_flux, date_joined = paste(dataset_flux$Month, dataset_flux$Day, dataset_flux$Year, dataset_flux$Time))
  })
  
# lubridate merged column
  dataset_date_lubridated <- reactive({
    dataset_date_joined <- dataset_date_joined()
    dataset_date_lubridated <- mutate(dataset_date_joined, date_joined_lubridated = lubridate::mdy_hms(dataset_date_joined$date_joined, tz = "UTC"))
  })
  
# filter by date, +1 is important due to issues with timezone setting
# filtering is based only on days
 dataset_date_filtered <- reactive({
   dataset_date_lubridated <- dataset_date_lubridated()
    dataset_date_filtered <- dplyr::filter(dataset_date_lubridated, date_joined_lubridated >= input$date_range[1] & date_joined_lubridated <= (input$date_range[2]+1)) %>%
      select(-date_joined)
  })

# timepoints with Mode=0 filtered  
 dataset_date_filtered_mode_ok <- reactive({
   dataset_date_filtered <- dataset_date_filtered()
   dataset_date_filtered_mode_ok <- dplyr::filter(dataset_date_filtered, Mode == 0) %>%
     mutate(CO2_flux = `CO2 Soil (ppm)` - `CO2 ATM (ppm)`) %>% 
     gather(data_type, CO2_ppm, `CO2 Soil (ppm)`, `CO2 ATM (ppm)`, `CO2_flux`) %>% 
     mutate(concentration = case_when(data_type == "CO2 Soil (ppm)" ~ "soil", data_type == "CO2 ATM (ppm)" ~ "atmospheric", data_type == "CO2_flux" ~ "flux"))
 })
 
# timepoints with Mode!=0 filtered
 dataset_date_filtered_mode_bad <- reactive({
   dataset_date_filtered <- dataset_date_filtered()
   dataset_date_filtered_mode_bad <- dplyr::filter(dataset_date_filtered, Mode != 0) %>% 
     select(date_joined_lubridated, Mode)
 })
 
 # average flux atmospheric  
 flux_average_atm <- reactive({
   flux <- summarySE(dataset_date_filtered_mode_ok(), measurevar = "CO2_ppm", groupvars = "concentration", conf.interval = 0.95)
   temp_upper <- flux[[1,3]]
 })
 
 # average flux soil  
 flux_average_soil <- reactive({
   flux <- summarySE(dataset_date_filtered_mode_ok(), measurevar = "CO2_ppm", groupvars = "concentration", conf.interval = 0.95)
   temp_upper <- flux[[3,3]]
 })
 
 # average temperature  
 temperature_average <- reactive({
   dataset_date_filtered_mode_ok <- dataset_date_filtered_mode_ok()
   temp <- mean(dataset_date_filtered_mode_ok$`Temperature (C)`)
 })
 
 # average flux  
 flux_average <- reactive({
   flux <- summarySE(dataset_date_filtered_mode_ok(), measurevar = "Flux", groupvars = "concentration", conf.interval = 0.95)
   temp_upper <- flux[[2,3]]
 })
 
 # flux option  
 concentration <- renderText({
   input$plot_type
 })
 
 # ggplot  
 ggplot_final <- reactive({
   dataset_date_filtered_mode_ok <- dataset_date_filtered_mode_ok()
   dataset_date_filtered_mode_ok$concentration <- factor(dataset_date_filtered_mode_ok$concentration, levels = c("soil", "atmospheric", "flux"))
   flux_average_atm <- flux_average_atm()
   flux_average_soil <- flux_average_soil()
   flux_average <- flux_average()
   concentration <- concentration()
   #temperature_average <- temperature_average()
   {if (concentration == "atmo_soil") {   # if atmo/soil concentration should be displayed
   ggplot(data = dataset_date_filtered_mode_ok, aes(y = CO2_ppm, x = date_joined_lubridated)) +
       geom_line(aes(colour = concentration), size = 1, alpha = 0.75, subset(dataset_date_filtered_mode_ok, concentration == "atmospheric" | concentration == "soil")) +
       scale_color_viridis_d() +
       {if (input$x_scale == "day") {
    scale_x_datetime(date_breaks = "1 day")
         } else {}} +
       {if (input$x_scale == "week") {
    scale_x_datetime(date_breaks = "1 week")
         } else {}} +
       {if (input$x_scale == "month") {
    scale_x_datetime(date_breaks = "1 month")
         } else {}} +
       {if (input$x_scale == "year") {
    scale_x_datetime(date_breaks = "1 year")
         } else {}} +
       labs(title = input$plot_title,
            subtitle = paste("mean atmospheric concentration - ",
                             round(flux_average_atm, digits = 1), "ppm CO2\n", "mean soil concentration - ",
                             round(flux_average_soil, digits = 1), "ppm CO2"), 
            x = "date", 
            y = (expression(paste(CO[2]," (ppm)", sep="")))) +
       theme_ipsum_rc() +
       theme(legend.position = "top", 
             legend.direction = "horizontal",
             axis.text.x = element_text(angle = 90)) +
       guides(fill = guide_legend(title = "concentration"))
     } else {   # if soil flux should be displayed
       ggplot(data = dataset_date_filtered_mode_ok, aes(y = Flux, x = date_joined_lubridated)) +
         geom_col(aes(colour = "#440154"), alpha = 0.5) +
         scale_color_viridis_d() +
         {if (input$x_scale == "day") {
         scale_x_datetime(date_breaks = "1 day")
           } else {}} +
         {if (input$x_scale == "week") {
         scale_x_datetime(date_breaks = "1 week")
           } else {}} +
         {if (input$x_scale == "month") {
         scale_x_datetime(date_breaks = "1 month")
           } else {}} +
         {if (input$x_scale == "year") {
         scale_x_datetime(date_breaks = "1 year")
           } else {}} +
         labs(title = input$plot_title,
              subtitle = paste("mean soil flux - ",
                               round(flux_average, digits = 1), "umol/m2/s CO2"), 
              x = "date", 
              y = (expression(paste(CO[2]," (", mu, "mol ", m^-2, s^-1,")", sep="")))) +
         theme_ipsum_rc() +
         theme(legend.position = "none",
               axis.text.x = element_text(angle = 90))
       }}
   })
  
# rendering plot 
 output$contents1 <- renderPlot({
   ggplot_final()
 })
 
# download, name of the file according to the date  
 output$download_plot <- downloadHandler(
     filename = function() {
       {if (input$download_extension == "pdf") {
         paste("soil_flux_", input$date_range[1], "_", input$date_range[2], sep = "", ".pdf")
       } else {
         if (input$download_extension == "png") {
           paste("soil_flux_", input$date_range[1], "_", input$date_range[2], sep = "", ".png")
           } else {
             if (input$download_extension == "svg") {
             paste("soil_flux_", input$date_range[1], "_", input$date_range[2], sep = "", ".svg")   
             }
             }
         }
         }
       },
   content = function(file) {
     {if (input$download_extension == "pdf") {
       ggsave(file, plot = ggplot_final(), device = "pdf", dpi = 300, height = 210, width = 297, units = "mm")
       } else {
         if (input$download_extension == "png") {
         ggsave(file, plot = ggplot_final(), device = "png", dpi = 300, height = 210, width = 297, units = "mm", scale = 0.4)
         } else {
           if (input$download_extension == "svg") {
             ggsave(file, plot = ggplot_final(), device = "svg", dpi = 300, height = 210, width = 297, units = "mm", scale = 0.4)
           }
         }
       }
     }
     }
 )
}