<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.net.InetAddress"%>
<%@page import="java.util.Date"%>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
    "http://www.w3.org/TR/html4/loose.dtd">

<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
        <title>Spring Web MVC - Load Balancing Demo</title>
    </head>

    <body>
        <h1>Load Balancing Demo</h1>
        <p>Esta pagina e servida por uma aplicacao Spring MVC rodando dentro de um dos containers Tomcat por tras do Nginx.</p>
        <p>Atualize a pagina algumas vezes e observe o hostname mudando entre as instancias.</p>
        <ul>
            <li><b>Hostname do container:</b> <%= InetAddress.getLocalHost().getHostName() %></li>
            <li><b>Horario do servidor:</b> <%= new Date() %></li>
        </ul>
    </body>
</html>
