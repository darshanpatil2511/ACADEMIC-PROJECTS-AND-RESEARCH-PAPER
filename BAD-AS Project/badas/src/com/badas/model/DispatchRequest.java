package com.badas.model;

public class DispatchRequest {
    private int id;
    private String patientName;
    private Integer patientId;
    private String location;
    private String symptoms;
    private String ambulanceType;
    private String severity;
    private String hospitalAssigned;
    private String status;
    private String dispatchedBy;
    private String createdAt;
    private String updatedAt;

    public DispatchRequest() {}

    public DispatchRequest(String patientName, String location, String symptoms,
                           String ambulanceType, String severity, String dispatchedBy) {
        this.patientName = patientName;
        this.location = location;
        this.symptoms = symptoms;
        this.ambulanceType = ambulanceType;
        this.severity = severity;
        this.dispatchedBy = dispatchedBy;
        this.status = "Pending";
    }

    public int getId() { return id; }
    public void setId(int id) { this.id = id; }

    public String getPatientName() { return patientName; }
    public void setPatientName(String patientName) { this.patientName = patientName; }

    public Integer getPatientId() { return patientId; }
    public void setPatientId(Integer patientId) { this.patientId = patientId; }

    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }

    public String getSymptoms() { return symptoms; }
    public void setSymptoms(String symptoms) { this.symptoms = symptoms; }

    public String getAmbulanceType() { return ambulanceType; }
    public void setAmbulanceType(String ambulanceType) { this.ambulanceType = ambulanceType; }

    public String getSeverity() { return severity; }
    public void setSeverity(String severity) { this.severity = severity; }

    public String getHospitalAssigned() { return hospitalAssigned; }
    public void setHospitalAssigned(String hospitalAssigned) { this.hospitalAssigned = hospitalAssigned; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getDispatchedBy() { return dispatchedBy; }
    public void setDispatchedBy(String dispatchedBy) { this.dispatchedBy = dispatchedBy; }

    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }

    public String getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(String updatedAt) { this.updatedAt = updatedAt; }

    @Override
    public String toString() {
        return "DispatchRequest{id=" + id + ", patient='" + patientName + "', status='" + status + "'}";
    }
}
