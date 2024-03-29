make_tab1 = function(data.AT) {

  
  # Set random number seed
  set.seed(0)
  
  # Do nonequilibrium and IRGA corrections
  faster = data.AT$AT_faster %>% 
    match_correct() %>% 
    noneq_correct_full(dt1_c = 1.58, dt2_c = 1.21, aV_c = 67.26, dt1_h = 2.23, dt2_h = 2.79, aV_h = 78.55)

  # Make AT dataframe
  data.AT = bind_rows(data.AT$AT_step, 
                      data.AT$AT_chamber, 
                      faster)
  data.AT$curveID = data.AT %>%  group_by(rep, method) %>% group_indices()
  data.AT = data.AT %>% select(curveID, rep, method, A, Tleaf)
  
  # Remove extreme outlier
  data.AT = subset(data.AT, rep != 141) 
  
  # Do the curve fitting necessary to extract  parameters of interest
  #pawar.params = fit.pawar(data.AT)
  print("Fitting curves, please wait...")
  dat = data.AT %>% rename(Photo = A)
  dat2 = list()
  j = 1
  for (i in unique(dat$curveID)) {
    cur = subset(dat, curveID == i)
    dat2[[j]] = as.data.frame(cur)
    j = j + 1
    
  }
  system.time({
    numcores = detectCores()
    clust <- makeCluster(numcores)
    clusterExport(clust, "nls_multstart")
    clusterExport(clust, "pawar_2018")
    clusterExport(clust, "select")
    results = parLapply(clust, dat2, fit_curves_parallel)
  })
  pawar.params = as.data.frame(do.call(rbind, results))
  print("Curve fitting complete")
  
  pawar.barplot.2 = gather(pawar.params, "parameter", "value", c(r_tref, e, eh, topt)) %>%
    group_by(method, parameter) %>%
    summarise(mean_param = mean(value), se = sd(value)/sqrt(length(value)),na.rm=T) #%>%
  
  # Fix names
  pawar.params$method[pawar.params$method == "step"] = "SEM"
  pawar.params$method[pawar.params$method == "chamber"] = "SEM-ATC"
  pawar.params$method[pawar.params$method == "faster"] = "FAsTeR"
  
  pawar.barplot.2$method[pawar.barplot.2$method == "step"] = "SEM"
  pawar.barplot.2$method[pawar.barplot.2$method == "chamber"] = "SEM-ATC"
  pawar.barplot.2$method[pawar.barplot.2$method == "faster"] = "FAsTeR"
  
  
  e_gathered = pawar.params %>%
    select(r_tref, e, eh, topt, curveID, rep, method)

  res.aov.rtref <- anova_test(data = e_gathered, dv = r_tref, wid = rep, within = method)
  res.aov.e <- anova_test(data = e_gathered, dv = e, wid = rep, within = method)
  res.aov.eh <- anova_test(data = e_gathered, dv = eh, wid = rep, within = method)
  res.aov.topt <- anova_test(data = e_gathered, dv = topt, wid = rep, within = method)
  # Assemble table
  
  res = e_gathered %>% group_by(method) %>% summarize(A_max = mean(r_tref),
                                                      E = mean(e),
                                                      E_D = mean(eh),
                                                      T_opt = mean(topt))

  res_se = e_gathered %>% group_by(method) %>% summarize(
                                                      A_max = sd(r_tref)/sqrt(length(r_tref)),
                                                      E = sd(e)/sqrt(length(e)),
                                                      E_D = sd(eh)/sqrt(length(eh)),
                                                      T_opt = sd(topt)/sqrt(length(topt))) 
  
  res = res[,2:5] %>% t() %>% as.data.frame()
  colnames(res) = c("Faster", "SEM", "SEM-ATC")
  res_se = res_se[,2:5] %>% t() %>% as.data.frame()
  colnames(res_se) = c("Faster StdErr", "SEM StdErr", "SEM-ATC StdErr")
  res = merge(res, res_se, by="row.names")
  res$p = NA
  
  res$p[1] = get_anova_table(res.aov.rtref)$p
  res$p[2] = get_anova_table(res.aov.e)$p
  res$p[3] = get_anova_table(res.aov.eh)$p
  res$p[4] = get_anova_table(res.aov.topt)$p
  
  #write.table(res, "stats.csv", sep=",", row.names = F)
  sink("stats.txt", append = T)
  cat("========\n")
  cat("Table 1:\n")
  cat("========\n\n")
  
  print(res)

  cat("\nTukey test for E_D:\n")
  
  # Then print tukey results - only E_D is signficant
  print(e_gathered %>% pairwise_t_test(eh ~ method, paired = TRUE))
  
  cat("\n\n")
  sink()

  
}