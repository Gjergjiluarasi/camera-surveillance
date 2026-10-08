#include <open62541/server.h>
#include <open62541/server_config_default.h>
#include <signal.h>
#include <stdio.h>

static volatile UA_Boolean running = true;

static void stopHandler(int sign) {
    (void)sign;
    running = false;
}

int main(void) {
    signal(SIGINT, stopHandler);
    signal(SIGTERM, stopHandler);

    UA_Server *server = UA_Server_new();
    if(!server) {
        fprintf(stderr, "Failed to create OPC UA server\n");
        return 1;
    }

    UA_StatusCode status = UA_ServerConfig_setDefault(UA_Server_getConfig(server));
    if(status != UA_STATUSCODE_GOOD) {
        fprintf(stderr, "Failed to configure server: 0x%08x\n", status);
        UA_Server_delete(server);
        return 1;
    }

    /* Add a sample variable: ns=1;s=Demo.Value */
    UA_Int32 initialValue = 42;
    UA_VariableAttributes attributes = UA_VariableAttributes_default;
    UA_Variant_setScalar(&attributes.value, &initialValue, &UA_TYPES[UA_TYPES_INT32]);
    attributes.displayName = UA_LOCALIZEDTEXT("en-US", "Demo Value");
    attributes.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;

    UA_NodeId variableId = UA_NODEID_STRING(1, "Demo.Value");
    UA_QualifiedName browseName = UA_QUALIFIEDNAME(1, "DemoValue");
    status = UA_Server_addVariableNode(server, variableId,
        UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER),
        UA_NODEID_NUMERIC(0, UA_NS0ID_ORGANIZES), browseName,
        UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE), attributes,
        NULL, NULL);
    if(status != UA_STATUSCODE_GOOD) {
        fprintf(stderr, "Failed to add sample variable: 0x%08x\n", status);
        UA_Server_delete(server);
        return 1;
    }

    printf("OPC UA server listening on opc.tcp://localhost:4840\n");
    status = UA_Server_run(server, &running);
    UA_Server_delete(server);
    return status == UA_STATUSCODE_GOOD ? 0 : 1;
}